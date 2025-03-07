{{ config(
    materialized='table' 
) }}

WITH casualties_data AS (
    SELECT 
        accident_id,
        age,
        class AS casualty_class,
        severity AS casualty_severity,
        mode AS casualty_type,
        age_band AS age_band_of_casualty,
        NULL AS sex_of_casualty
    FROM {{ ref('stg_casualties') }}
)

SELECT * FROM casualties_data
