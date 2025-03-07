with source as (
    select
        accident_id,
        jsonb_array_elements(casualties) as casualty
    from {{ source('tfl_data', 'stg_tfl_accidents') }}
),
exploded as (
    select
        accident_id,
        casualty->>'age' as age,
        casualty->>'mode' as mode,
        casualty->>'class' as class,
        casualty->>'ageBand' as age_band,
        casualty->>'severity' as severity
    from source
)
select * from exploded