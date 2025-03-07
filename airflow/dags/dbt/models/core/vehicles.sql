WITH vehicle_data AS (
    SELECT 
        unique_accident_id,  -- Ensures correct accident correlation
        accident_id,
        vehicle_type
    FROM {{ ref('stg_vehicles') }}
)

SELECT * FROM vehicle_data
