-- One row per station, all systems. Focus stations (NYCU) flagged from the seed.

with stations as (

    select * from {{ ref('stg_youbike__stations') }}
    union all
    select * from {{ ref('stg_velib__stations') }}

)

select
    stations.station_key,
    stations.system_id,
    systems.city,
    systems.country,
    stations.station_uid,
    stations.station_name,
    stations.station_name_local,
    coalesce(focus.short_name, stations.station_name) as display_name,
    stations.latitude,
    stations.longitude,
    stations.capacity,
    focus.station_key is not null                     as is_focus,
    focus.focus_group,
    stations.last_seen_at
from stations
inner join {{ ref('systems') }} as systems
    on stations.system_id = systems.system_id
left join {{ ref('focus_stations') }} as focus
    on stations.station_key = focus.station_key
