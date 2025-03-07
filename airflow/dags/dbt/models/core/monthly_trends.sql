{{ config(
    materialized='table'
) }}

WITH monthly_accidents AS (
    SELECT 
        DATE_TRUNC('month', accident_date) AS accident_month,
        COUNT(accident_id) AS accident_count
    FROM {{ ref('accident_summary') }}  -- Use finalized accident summary table
    GROUP BY accident_month
    ORDER BY accident_month
)

SELECT * FROM monthly_accidents
