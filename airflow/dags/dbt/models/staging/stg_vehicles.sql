WITH source AS (
    SELECT *
    FROM {{ source('tfl_data', 'stg_tfl_accidents') }}
),

exploded_vehicles AS (
    SELECT
        accident_id,
        CAST(accident_id AS VARCHAR) AS unique_accident_id,
        jsonb_array_elements(vehicles::jsonb) ->> 'type' AS vehicle_type
    FROM source
)

SELECT * FROM exploded_vehicles