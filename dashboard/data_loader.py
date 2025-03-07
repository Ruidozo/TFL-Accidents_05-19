import os
import pandas as pd
import psycopg2
import sqlalchemy
from sqlalchemy import create_engine
from dotenv import load_dotenv

# ✅ Load environment variables
load_dotenv("/usr/app/.env")

# ✅ Database connection settings
DB_HOST = os.getenv("DB_HOST", "postgres_db_tfl_accident_data")  
DB_PORT = os.getenv("DB_PORT", "5432")  
DB_NAME = os.getenv("DB_NAME", "tfl_accidents")
DB_USER = os.getenv("DB_USER", "odiurdigital")
DB_PASSWORD = os.getenv("DB_PASSWORD", "local")

# ✅ Create SQLAlchemy engine
engine = create_engine(f"postgresql+psycopg2://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}")

# ✅ Function to fetch data from PostgreSQL
def fetch_data(query):
    """Execute SQL query and return results as a Pandas DataFrame."""
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD
        )
        df = pd.read_sql(query, conn)
        conn.close()
        return df
    except psycopg2.OperationalError as e:
        print(f"Database connection error: {e}")
        return pd.DataFrame()

# ✅ Example Queries (can be used inside app.py)

def get_yearly_trends(where_clause=""):
    """Retrieve accident counts per year, supporting 'All Years'."""
    query = f"""
        SELECT EXTRACT(YEAR FROM accident_date) AS accident_year, 
               COUNT(accident_id) AS accident_count
        FROM accident_summary
        {where_clause}  -- Applies the filters dynamically
        GROUP BY accident_year
        ORDER BY accident_year;
    """
    return fetch_data(query)

def get_global_quarterly_trends():
    """Retrieve accident counts grouped by quarters across all years."""
    query = """
        SELECT 
            TO_CHAR(accident_date, 'YYYY') AS quarter_label,
            COUNT(accident_id) AS accident_count
        FROM accident_summary
        GROUP BY quarter_label
        ORDER BY quarter_label;
    """
    return fetch_data(query)

def get_monthly_trends(where_clause=""):
    query = """
    SELECT TO_CHAR(accident_date, 'Month') AS month_name, 
           EXTRACT(MONTH FROM accident_date) AS month_number, 
           COUNT(accident_id) AS accident_count 
    FROM accident_summary
    """
    if where_clause:
        query += f" {where_clause}"
    query += " GROUP BY month_name, month_number ORDER BY month_number;"
    
    try:
        df = pd.read_sql(query, con=engine)
        return df
    except sqlalchemy.exc.DatabaseError as e:
        print(f"Database error: {e}")
        return pd.DataFrame()


def get_top_hotspots():
    """Retrieve top accident-prone locations."""
    query = "SELECT location, accident_count FROM hotspots ORDER BY accident_count DESC LIMIT 10;"
    return fetch_data(query)

def get_top_accident_prone_streets():
    """Retrieve top 10 accident-prone streets with borough information."""
    query = """
        SELECT borough, location AS street_name, COUNT(accident_id) AS accident_count
        FROM accident_summary
        GROUP BY borough, location
        ORDER BY accident_count DESC
        LIMIT 10;
    """
    return fetch_data(query)

def get_filter_options():
    """Retrieve distinct values for filtering options."""
    query = """
        SELECT DISTINCT 
            EXTRACT(YEAR FROM accident_date) AS year,
            borough,
            accident_severity,
            vehicle_type
        FROM accident_summary
        LEFT JOIN vehicles ON accident_summary.accident_id = vehicles.accident_id
        ORDER BY year DESC;
    """
    return fetch_data(query)

def get_severity_breakdown(where_clause=""):
    """Retrieve accident counts by severity dynamically based on filters."""
    query = f"""
        SELECT accident_severity, COUNT(accident_id) AS count
        FROM accident_summary
        {where_clause}  -- Applies the filters dynamically
        GROUP BY accident_severity
        ORDER BY count DESC;
    """
    return fetch_data(query)

def get_transport_mode_distribution(where_clause=""):
    """Retrieve accident counts by transport type dynamically based on filters."""
    query = f"""
        SELECT vehicles.vehicle_type, COUNT(vehicles.accident_id) AS count
        FROM vehicles
        LEFT JOIN accident_summary ON vehicles.accident_id = accident_summary.accident_id
        {where_clause}  -- Applies the filters dynamically
        GROUP BY vehicles.vehicle_type
        ORDER BY count DESC;
    """
    return fetch_data(query)

def get_borough_summary(where_clause=""):
    """Retrieve borough-wise accident summary with severity breakdown."""
    
    query = f"""
        SELECT 
            borough,
            COUNT(accident_id) AS total_accidents,
            SUM(CASE WHEN accident_severity = 'Slight' THEN 1 ELSE 0 END) AS slight_accidents,
            SUM(CASE WHEN accident_severity = 'Serious' THEN 1 ELSE 0 END) AS serious_accidents,
            SUM(CASE WHEN accident_severity = 'Fatal' THEN 1 ELSE 0 END) AS fatal_accidents
        FROM accident_summary
        {where_clause}
        GROUP BY borough
        ORDER BY total_accidents DESC;
    """
    return fetch_data(query)

def get_accident_locations(where_clause=""):
    """Retrieve accident latitude & longitude, automatically limiting large datasets."""
    
    query_count = f"SELECT COUNT(*) AS total FROM accident_summary {where_clause};"
    df_count = fetch_data(query_count)

    # ✅ Ensure `total_accidents` exists before unpacking
    total_accidents = df_count.iloc[0]["total"] if not df_count.empty else 0

    # ✅ Adjust limit based on total data size
    limit = 5000 if total_accidents > 10000 else total_accidents  

    query = f"""
        SELECT latitude, longitude
        FROM accident_summary
        {where_clause}
        ORDER BY accident_date DESC
        LIMIT {limit};
    """
    df_locations = fetch_data(query)

    return df_locations, total_accidents

def get_weather_accident_trends(where_clause="", by_severity=False):
    """Retrieve accident trends based on weather conditions. 
    If `by_severity=True`, the query groups by severity level."""

    if by_severity:
        query = f"""
            SELECT 
                CASE 
                    WHEN precipitation > 0 THEN 'Rainy'
                    WHEN snow_depth > 0 THEN 'Snowy'
                    WHEN sunshine_duration > 3 THEN 'Sunny'
                    ELSE 'Cloudy'
                END AS weather_category,
                accident_severity,
                COUNT(accident_id) AS accident_count
            FROM accident_summary
            {where_clause}
            GROUP BY weather_category, accident_severity
            ORDER BY weather_category, accident_severity;
        """
    else:
        query = f"""
            SELECT 
                CASE 
                    WHEN precipitation > 0 THEN 'Rainy'
                    WHEN snow_depth > 0 THEN 'Snowy'
                    WHEN sunshine_duration > 3 THEN 'Sunny'
                    ELSE 'Cloudy'
                END AS weather_category,
                COUNT(accident_id) AS accident_count
            FROM accident_summary
            {where_clause}
            GROUP BY weather_category
            ORDER BY accident_count DESC;
        """

    return fetch_data(query)

def get_weekday_vs_weekend_trends(where_clause=""):
    """Fetch and compare weekday vs. weekend accident counts."""

    query = f"""
        SELECT 
            CASE 
                WHEN EXTRACT(DOW FROM accident_date) IN (0, 6) THEN 'Weekend'
                ELSE 'Weekday'
            END AS day_type,
            COUNT(*) AS accident_count
        FROM accident_summary
        {where_clause}
        GROUP BY day_type
        ORDER BY accident_count DESC;
    """

    return fetch_data(query)

def get_high_risk_days(where_clause=""):
    """Fetch and rank accident occurrences by weekday."""
    
    query = f"""
        SELECT 
            CASE EXTRACT(DOW FROM accident_date)
                WHEN 0 THEN 'Sunday'
                WHEN 1 THEN 'Monday'
                WHEN 2 THEN 'Tuesday'
                WHEN 3 THEN 'Wednesday'
                WHEN 4 THEN 'Thursday'
                WHEN 5 THEN 'Friday'
                WHEN 6 THEN 'Saturday'
            END AS weekday,
            COUNT(*) AS accident_count
        FROM accident_summary
        {where_clause}
        GROUP BY weekday
        ORDER BY accident_count DESC;
    """
    
    return fetch_data(query)

def get_accidents_by_age_group(where_clause=""):
    """Fetch accident count per age group from casualties table."""

    query = """
    SELECT 
        CASE 
                WHEN CAST(age AS INTEGER) BETWEEN 0 AND 10 THEN '0-10'
                WHEN CAST(age AS INTEGER) BETWEEN 11 AND 20 THEN '11-20'
                WHEN CAST(age AS INTEGER) BETWEEN 21 AND 30 THEN '21-30'
                WHEN CAST(age AS INTEGER) BETWEEN 31 AND 40 THEN '31-40'
                WHEN CAST(age AS INTEGER) BETWEEN 41 AND 50 THEN '41-50'
                WHEN CAST(age AS INTEGER) BETWEEN 51 AND 60 THEN '51-60'
                WHEN CAST(age AS INTEGER) BETWEEN 61 AND 70 THEN '61-70'
                WHEN CAST(age AS INTEGER) > 70 THEN '70+'
                ELSE 'Unknown'
            END AS age_group,
            COUNT(*) AS accident_count
        FROM casualties
        GROUP BY age_group
        ORDER BY age_group;
    """
    
    return fetch_data(query)

def get_fatalities_by_age(where_clause):
    """Retrieve fatality counts grouped by age group."""
    query = """
        SELECT 
            CASE 
                WHEN CAST(c.age AS INTEGER) BETWEEN 0 AND 10 THEN '0-10'
                WHEN CAST(c.age AS INTEGER) BETWEEN 11 AND 20 THEN '11-20'
                WHEN CAST(c.age AS INTEGER) BETWEEN 21 AND 30 THEN '21-30'
                WHEN CAST(c.age AS INTEGER) BETWEEN 31 AND 40 THEN '31-40'
                WHEN CAST(c.age AS INTEGER) BETWEEN 41 AND 50 THEN '41-50'
                WHEN CAST(c.age AS INTEGER) BETWEEN 51 AND 60 THEN '51-60'
                WHEN CAST(c.age AS INTEGER) BETWEEN 61 AND 70 THEN '61-70'
                WHEN CAST(c.age AS INTEGER) > 70 THEN '70+'
                ELSE 'Unknown'
            END AS age_group,
            COUNT(*) AS fatality_count
        FROM casualties c
        JOIN accidents a ON c.accident_id = a.accident_id
        WHERE a.accident_severity = 'Fatal'
        GROUP BY age_group
        ORDER BY age_group;
    """
    return fetch_data(query)