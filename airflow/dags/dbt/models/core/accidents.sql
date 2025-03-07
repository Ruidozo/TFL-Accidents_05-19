{{ config(
    materialized='table'
) }}

WITH source AS (
    SELECT * 
    FROM {{ ref('stg_accidents') }}  
),

weather_data AS (
    SELECT 
        date AS weather_date,  -- Match format with `stg_accidents.date`
        temperature,
        humidity,
        wind_speed,
        precipitation,
        pressure,
        cloud_cover,
        radiation,
        snow_depth,
        sunshine_duration
    FROM public.london_weather
),

cleaned_accidents AS (
    SELECT
        s.accident_id,
        CAST(EXTRACT(YEAR FROM s.accident_date) AS VARCHAR) || '-' || CAST(s.accident_id AS VARCHAR) AS unique_accident_id,
        s.accident_date AS date,
        s.location,
        s.lon AS longitude,
        s.lat AS latitude,
        s.borough,
        s.severity AS accident_severity,

        -- Join Weather Data
        COALESCE(wd.temperature, 0) AS temperature,
        COALESCE(wd.humidity, 0) AS humidity,
        COALESCE(wd.wind_speed, 0) AS wind_speed,
        COALESCE(wd.precipitation, 0) AS precipitation,
        COALESCE(wd.pressure, 0) AS pressure,
        COALESCE(wd.cloud_cover, 0) AS cloud_cover,
        COALESCE(wd.radiation, 0) AS radiation,
        COALESCE(wd.snow_depth, 0) AS snow_depth,
        COALESCE(wd.sunshine_duration, 0) AS sunshine_duration

    FROM source s
    LEFT JOIN weather_data wd
    ON s.accident_date = wd.weather_date  -- Ensure date formats match
)

SELECT * FROM cleaned_accidents