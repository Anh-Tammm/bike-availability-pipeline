-- One row per NYCU focus station per snapshot (~20 min), in local time.
-- Lets the dashboard show the real situation on a chosen day.
-- Reads the small YouBike staging table only.

select
    stations.station_key,
    stations.display_name,
    stations.capacity,
    snapshots.collected_at,
    datetime(snapshots.collected_at, systems.timezone)       as collected_at_local,
    date(snapshots.collected_at, systems.timezone)           as local_date,
    snapshots.is_in_service,
    snapshots.bikes_available,
    snapshots.docks_available
from {{ ref('stg_youbike__availability') }} as snapshots
inner join {{ ref('dim_stations') }} as stations
    on concat(snapshots.system_id, ':', snapshots.station_uid) = stations.station_key
inner join {{ ref('systems') }} as systems
    on snapshots.system_id = systems.system_id
where stations.is_focus
