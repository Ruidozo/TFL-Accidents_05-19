WITH source AS (
    SELECT * 
    FROM {{ ref('stg_accidents') }}  -- Ensure this matches the correct model name
),

cleaned_accidents AS (
    SELECT
        accident_id,
        CAST(EXTRACT(YEAR FROM accident_date) AS VARCHAR) || '-' || CAST(accident_id AS VARCHAR) AS unique_accident_id,
        accident_date AS date,
        location,
        lon AS longitude,
        lat AS latitude,
        borough,
        severity AS accident_severity  -- Update this line
    FROM source
)

SELECT * FROM cleaned_accidents