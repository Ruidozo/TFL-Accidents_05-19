{{ config(
    materialized='table'
) }}

WITH accident_data AS (
    SELECT 
        a.accident_id,
        DATE(a.date) AS accident_date,  -- Convert timestamp to date for faster joins
        a.location,
        a.longitude,
        a.latitude,
        a.borough,
        a.accident_severity,
        COUNT(DISTINCT v.vehicle_type) AS vehicle_count,
        COUNT(*) AS casualty_count
    FROM {{ ref('accidents') }} a
    LEFT JOIN {{ ref('vehicles') }} v ON a.accident_id = v.accident_id
    LEFT JOIN {{ ref('casualties') }} c ON a.accident_id = c.accident_id
    GROUP BY a.accident_id, a.location, a.longitude, a.latitude, a.date, a.borough, a.accident_severity
),

weather_data AS (
    SELECT 
        DATE(date) AS weather_date,  -- Convert timestamp to date for consistent join
        temperature,
        humidity,
        wind_speed,
        precipitation,
        sunshine_duration,
        snow_depth
    FROM public.london_weather
),

accident_weather AS (
    SELECT 
        ad.*,
        COALESCE(wd.temperature, 0) AS temperature,  -- Fill missing values with defaults
        COALESCE(wd.humidity, 0) AS humidity,
        COALESCE(wd.wind_speed, 0) AS wind_speed,
        COALESCE(wd.precipitation, 0) AS precipitation,
        COALESCE(wd.sunshine_duration, 0) AS sunshine_duration,
        COALESCE(wd.snow_depth, 0) AS snow_depth
    FROM accident_data ad
    LEFT JOIN weather_data wd
    ON ad.accident_date = wd.weather_date
)

SELECT * FROM accident_weather
