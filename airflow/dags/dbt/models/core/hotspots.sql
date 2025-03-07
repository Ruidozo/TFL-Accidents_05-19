{{ config(
    materialized='table'
) }}

WITH location_accidents AS (
    SELECT 
        location,  -- Street or intersection where the accident occurred
        borough,
        COUNT(accident_id) AS accident_count
    FROM {{ ref('accident_summary') }}  -- Use finalized accident summary table
    GROUP BY location, borough
    ORDER BY accident_count DESC
)

SELECT * FROM location_accidents
