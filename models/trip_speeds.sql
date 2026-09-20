select
    trip_id,
    distance_miles,
    duration_mins,
    round((distance_miles / duration_mins) * 600, 2) as avg_speed_mph
from {{ ref('trips') }}