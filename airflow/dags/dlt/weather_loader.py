import pandas as pd
from google.cloud import storage
import psycopg2
import os
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")

# PostgreSQL Configuration (Local)
DB_HOST = os.getenv("DB_HOST")
DB_PORT = os.getenv("DB_PORT")
DB_NAME = os.getenv("DB_NAME")
DB_USER = os.getenv("DB_USER")
DB_PASSWORD = os.getenv("DB_PASSWORD")

# Google Cloud Storage Configuration
GCS_BUCKET = os.getenv("GCS_BUCKET")
GCS_CSV_PATH = os.getenv("GCS_CSV_PATH")

# Local file path
LOCAL_CSV_PATH = "/opt/airflow/dags/dlt/london_weather_data_1979_to_2023.csv"

# Load CSV file
def load_weather_data():
    logging.info("📂 Loading weather data from local CSV file...")

    # Load CSV with correct column names
    df = pd.read_csv(LOCAL_CSV_PATH)

    # Convert date column from int (YYYYMMDD) to actual Date
    df["DATE"] = pd.to_datetime(df["DATE"], format="%Y%m%d")

    # Rename columns to match PostgreSQL table
    df.rename(columns={
        "DATE": "date",
        "TG": "temperature",
        "HU": "humidity",
        "CC": "cloud_cover",
        "TX": "max_temp",
        "TN": "min_temp",
        "RR": "precipitation",
        "PP": "pressure",
        "QQ": "radiation",
        "SD": "snow_depth",
        "SS": "sunshine_duration",
    }, inplace=True)

    # Upload to Google Cloud Storage
    logging.info("☁️ Uploading CSV file to Google Cloud Storage...")
    try:
        storage_client = storage.Client()
        bucket = storage_client.bucket(GCS_BUCKET)
        blob = bucket.blob(f"{GCS_CSV_PATH}london_weather_data_1979_to_2023.csv")
        blob.upload_from_filename(LOCAL_CSV_PATH)
        logging.info("✅ File uploaded to GCS successfully.")
    except Exception as e:
        logging.error(f"❌ Failed to upload to GCS: {e}")

    # Load data to PostgreSQL
    logging.info("🗃️ Loading data into PostgreSQL...")
    try:
        conn = psycopg2.connect(
            dbname=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            host=DB_HOST,
            port=DB_PORT
        )
        cursor = conn.cursor()

        # Create table if it doesn't exist
        # ...existing code...
        # ...existing code...
        create_table_query = """
        DROP TABLE IF EXISTS london_weather;
        CREATE TABLE london_weather (
            id SERIAL PRIMARY KEY,
            date DATE,
            temperature FLOAT,
            humidity FLOAT,
            wind_speed FLOAT,   -- Placeholder (no data in CSV)
            precipitation FLOAT,
            pressure FLOAT,
            cloud_cover FLOAT,
            radiation FLOAT,
            snow_depth FLOAT,
            sunshine_duration FLOAT
        );
        """
        cursor.execute(create_table_query)

        # Insert data into PostgreSQL
        for _, row in df.iterrows():
            cursor.execute("""
                INSERT INTO london_weather (date, temperature, humidity, precipitation, pressure, cloud_cover, radiation, snow_depth, sunshine_duration)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            """, (
                row['date'], row['temperature'], row['humidity'],
                row['precipitation'], row['pressure'], row['cloud_cover'],
                row['radiation'], row['snow_depth'], row['sunshine_duration']
            ))

        conn.commit()
        cursor.close()
        conn.close()
        logging.info("✅ Data loaded into PostgreSQL successfully.")

    except Exception as e:
        logging.error(f"❌ Database operation failed: {e}")

if __name__ == "__main__":
    load_weather_data()