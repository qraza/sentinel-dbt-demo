select *
from {{ ref('trip_speeds') }}
where avg_speed_mph > 100