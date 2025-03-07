import os
import logging
import requests
import yaml
import json
import pandas as pd
import gzip
import shutil
import psycopg2
import psycopg2.extras
import ast
from google.cloud import storage
from datetime import datetime
from io import StringIO
from dotenv import load_dotenv


# Load configuration
try:
    config_path = os.path.join(os.path.dirname(__file__), "config.yaml")
    with open(config_path, "r") as f:
        config = yaml.safe_load(f)
        if config is None:
            raise ValueError("Configuration file is empty")
except FileNotFoundError:
    print("❌ Configuration file 'config.yaml' not found.")
    exit(1)
except ValueError as e:
    print(f"❌ {e}")
    exit(1)

# Extract config values
TFL_API_URL = config["tfl_api_url"]
START_YEAR = config["start_year"]
END_YEAR = config["end_year"]
GCS_BUCKET = config["gcs_bucket"],
LOCAL_STORAGE = config["local_storage"]
RAW_JSONL_STORAGE = os.path.join(LOCAL_STORAGE, "raw/jsonl")
RAW_CSV_STORAGE = os.path.join(LOCAL_STORAGE, "raw/csv")

# Ensure directories exist
os.makedirs(RAW_JSONL_STORAGE, exist_ok=True)
os.makedirs(RAW_CSV_STORAGE, exist_ok=True)

# Load environment variables
env_path = os.path.join(os.path.dirname(__file__), ".env")
load_dotenv(dotenv_path=env_path)

GCS_BUCKET = os.getenv('GCS_BUCKET')
if not GCS_BUCKET:
    raise ValueError("GCS_BUCKET environment variable is not set.")

# Load database credentials
#FIXME: CHECK IF THIS IS CAUSING THE POSTRES ISSUE
DB_PARAMS = {
    "dbname": os.getenv("DB_NAME"),
    "user": os.getenv("DB_USER"),
    "password": os.getenv("DB_PASSWORD"),
    "host": os.getenv("DB_HOST"),
    "port": os.getenv("DB_PORT")
}

# Logging configuration
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")

logging.basicConfig(
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S',
    level=logging.INFO
)

logging.info("🚀 Starting data ingestion pipeline...")


def fetch_tfl_data(year):
    """Fetch accident data for a specific year from the TFL API."""
    url = f"{TFL_API_URL}/{year}"
    response = requests.get(url)
    
    if response.status_code == 200:
        return response.json()
    else:
        print(f"❌ Failed to fetch data for {year}. Status: {response.status_code}")
        return []

def save_jsonl(data, file_path):
    """Saves data in JSONL format without modification."""
    with gzip.open(file_path, "wt", encoding="utf-8") as f:
        for record in data:
            f.write(json.dumps(record) + "\n")
    print(f"✅ Stored RAW JSONL: {file_path}")

def save_csv(data, file_path):
    """Saves data in CSV format and compresses it."""
    df = pd.DataFrame(data)
    compressed_file_path = file_path + ".gz"
    with gzip.open(compressed_file_path, "wt", encoding="utf-8") as f:
        df.to_csv(f, index=False)
    print(f"✅ Stored RAW CSV: {compressed_file_path}")
    return compressed_file_path

def upload_to_gcs(data_type="jsonl", file_path=None, year=None):
    """Uploads JSONL and CSV data to Google Cloud Storage, organized per year."""
    client = storage.Client()
    bucket = client.bucket(GCS_BUCKET.strip())
    if data_type == "jsonl":
        folder = f"raw/jsonl/tfl_accidents_{year}.jsonl.gz"
    elif data_type == "csv":
        folder = f"raw/csv/tfl_accidents_{year}.csv.gz"
    else:
        print("❌ Invalid data type specified for upload.")
        return

    blob = bucket.blob(folder)
    blob.chunk_size = 10 * 1024 * 1024  # ✅ Set chunk size correctly
    blob.upload_from_filename(file_path, timeout=300)

    print(f"✅ Uploaded {data_type.upper()} file: {file_path} to GCS ({folder}).")

def connect_db():
    """Establish a connection to PostgreSQL."""
    try:
        conn = psycopg2.connect(**DB_PARAMS)
        logging.info(f"✅ Connected to PostgreSQL")
        return conn
    except Exception as e:
        logging.error(f"❌ Database connection failed: {e}")
        return None

def recreate_table(table_name="public.stg_tfl_accidents"):
    """Drop and recreate the PostgreSQL table to ensure the correct schema."""
    conn = connect_db()
    if not conn:
        return

    try:
        drop_table_sql = f"DROP TABLE IF EXISTS {table_name};"
        create_table_sql = f"""
            CREATE TABLE {table_name} (
                accident_id INTEGER PRIMARY KEY,
                lat FLOAT,
                lon FLOAT,
                location TEXT,
                accident_date TIMESTAMP,
                severity TEXT,
                borough TEXT,
                casualties JSONB, -- Stored as structured JSON
                vehicles JSONB -- Stored as structured JSON
            );
        """
        cur = conn.cursor()
        cur.execute(drop_table_sql)
        cur.execute(create_table_sql)
        conn.commit()
        cur.close()
        logging.info(f"✅ Table `{table_name}` recreated successfully.")
    except Exception as e:
        logging.error(f"❌ Error creating table `{table_name}`: {e}")
    finally:
        conn.close()

def sanitize_json_field(field):
    """Sanitize and clean JSON-like fields, removing unnecessary keys."""
    if pd.isna(field) or field.strip() == "":
        return None
    try:
        parsed = ast.literal_eval(field)  # Convert to Python object
        if isinstance(parsed, list):
            cleaned_data = [{k: v for k, v in item.items() if k != "$type"} for item in parsed]
            return json.dumps(cleaned_data)
        return json.dumps(parsed)
    except (ValueError, SyntaxError):
        logging.warning(f"⚠️ Could not parse JSON field: {field}")
        return None   

def get_local_files():
    """List all GZipped CSV files in the RAW_CSV_STORAGE directory."""
    local_files = [f for f in os.listdir(RAW_CSV_STORAGE) if f.endswith(".csv.gz")]
    logging.info(f"📂 Found {len(local_files)} compressed CSV files in `{RAW_CSV_STORAGE}`.")
    return local_files

def extract_gz_file(gz_file_path):
    """Extract a GZipped CSV file."""
    local_csv_path = gz_file_path.replace(".gz", "")

    try:
        with gzip.open(gz_file_path, "rb") as f_in, open(local_csv_path, "wb") as f_out:
            shutil.copyfileobj(f_in, f_out)
        os.remove(gz_file_path)  # Remove compressed file after extraction
        logging.info(f"✅ Extracted `{local_csv_path}`.")
        return local_csv_path
    except Exception as e:
        logging.error(f"❌ Failed to extract `{gz_file_path}`: {e}")
        return None

def clean_and_transform_data(df):
    """Transform data to match PostgreSQL schema."""
    if "$type" in df.columns:
        df.drop(columns=["$type"], inplace=True)

    rename_mapping = {
        "id": "accident_id",
        "date": "accident_date"
    }
    df.rename(columns=rename_mapping, inplace=True)

    expected_columns = [
        "accident_id", "lat", "lon", "location", "accident_date",
        "severity", "borough", "casualties", "vehicles"
    ]
    df = df[[col for col in expected_columns if col in df.columns]]

    df["accident_id"] = pd.to_numeric(df["accident_id"], errors="coerce").dropna().astype(int)
    df["accident_date"] = pd.to_datetime(df["accident_date"], errors="coerce")

    for json_col in ["casualties", "vehicles"]:
        if json_col in df.columns:
            df[json_col] = df[json_col].apply(sanitize_json_field)

    return df

def load_csv_in_batches(file_path, table_name="public.stg_tfl_accidents", batch_size=10000):
    """Load CSV file into PostgreSQL in batches."""
    conn = connect_db()
    if not conn:
        return

    try:
        chunk_iterator = pd.read_csv(file_path, chunksize=batch_size)

        total_rows = 0
        for chunk in chunk_iterator:
            logging.debug(f"Columns in DataFrame: {chunk.columns.tolist()}")
            chunk = clean_and_transform_data(chunk)

            csv_buffer = StringIO()
            chunk.to_csv(csv_buffer, index=False, header=False, sep='\t')
            csv_buffer.seek(0)

            copy_sql = f"""
                COPY {table_name} (accident_id, lat, lon, location, accident_date, severity, borough, casualties, vehicles)
                FROM STDIN WITH CSV DELIMITER E'\t' NULL 'NULL' QUOTE '"';
            """
            cur = conn.cursor()
            cur.copy_expert(copy_sql, csv_buffer)
            conn.commit()

            total_rows += len(chunk)
            logging.info(f"✅ Uploaded {len(chunk)} rows, Total: {total_rows}")

        cur.close()
        logging.info(f"🎯 Finished loading `{file_path}`: {total_rows} rows uploaded.")
    except Exception as e:
        logging.error(f"❌ Error loading `{file_path}`: {e}")
        conn.rollback()
    finally:
        conn.close()

def load_tfl_data():
    """Pipeline to fetch and store raw accident data."""
    for year in range(START_YEAR, END_YEAR + 1):
        print(f"📡 Fetching data for {year}...")
        data = fetch_tfl_data(year)

        if not data:
            print(f"⚠️ No data found for {year}. Skipping.")
            continue

        # Store raw JSONL & CSV files
        jsonl_file_path = os.path.join(RAW_JSONL_STORAGE, f"tfl_accidents_{year}.jsonl.gz")
        csv_file_path = os.path.join(RAW_CSV_STORAGE, f"tfl_accidents_{year}.csv")

        save_jsonl(data, jsonl_file_path)
        compressed_csv_file_path = save_csv(data, csv_file_path)

        # Upload files to GCS

        upload_to_gcs(data_type="jsonl", file_path=jsonl_file_path, year=year)
        upload_to_gcs(data_type="csv", file_path=compressed_csv_file_path, year=year)

    print("🎯 Data ingestion completed successfully!")

def process_pipeline():
    """End-to-end pipeline: recreate table, process local CSV files, and load them into PostgreSQL."""
    recreate_table()

    local_files = get_local_files()
    if not local_files:
        logging.warning("⚠️ No GZipped CSV files found in RAW_CSV_STORAGE.")
        return

    for local_file in local_files:
        local_gz_path = os.path.join(RAW_CSV_STORAGE, local_file)
        local_csv_path = extract_gz_file(local_gz_path)
        if not local_csv_path:
            continue

        logging.info(f"📄 Processing `{local_csv_path}`...")
        load_csv_in_batches(local_csv_path)
        os.remove(local_csv_path) # Remove CSV file after loading

if __name__ == "__main__":
    logging.info("🚀 Starting data ingestion pipeline...")
    load_tfl_data()
    process_pipeline()
    logging.info("🎯 Pipeline finished.")
