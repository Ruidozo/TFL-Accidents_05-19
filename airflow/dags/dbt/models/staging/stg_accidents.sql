with source as (
    select * from {{ source('tfl_data', 'stg_tfl_accidents') }}
)
select * from source