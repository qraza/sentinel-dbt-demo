{{ config(materialized='view') }}

with failing as (
    select
        a.trip_id,
        a.distance_miles,
        a.duration_mins,
        a.avg_speed_mph
    from {{ target.database }}.{{ target.schema }}_dbt_test__audit.assert_speed_is_plausible a
    inner join {{ ref('trip_speeds') }} t
      on a.trip_id = t.trip_id
     and t.avg_speed_mph > 100
    limit {{ var('sentinel_sample_limit', 20) }}
)
select
    'test.sentinel_demo.assert_speed_is_plausible' as test_unique_id,
    'assert_speed_is_plausible'                    as test_name,
    'singular'                                     as test_type,
    'trip_speeds'                                  as guarded_model,
    count(*)                                       as failure_count,
    to_json(array_agg(object_construct(
        'trip_id',        trip_id::varchar,
        'distance_miles', distance_miles::varchar,
        'duration_mins',  duration_mins::varchar,
        'avg_speed_mph',  avg_speed_mph::varchar
    )))                                            as failing_rows
from failing
having count(*) > 0