{{ config(materialized='view') }}

-- All systems in one common shape, with local time (needed to analyse "5 pm").

with snapshots as (

    select system_id, station_uid, snapshot_id, collected_at, snapshot_date, is_in_service,
           bikes_available, docks_available, bikes_mechanical, bikes_electric
    from {{ ref('stg_youbike__availability') }}

    union all

    select system_id, station_uid, snapshot_id, collected_at, snapshot_date, is_in_service,
           bikes_available, docks_available, bikes_mechanical, bikes_electric
    from {{ ref('stg_velib__station_status') }}

)

select
    concat(snapshots.system_id, ':', snapshots.snapshot_id)   as snapshot_key,
    concat(snapshots.system_id, ':', snapshots.station_uid)   as station_key,
    snapshots.system_id,
    snapshots.station_uid,
    snapshots.collected_at,
    snapshots.snapshot_date,
    datetime(snapshots.collected_at, systems.timezone)        as collected_at_local,
    extract(hour from datetime(snapshots.collected_at, systems.timezone)) as local_hour,
    -- BigQuery: 1 = Sunday ... 7 = Saturday
    extract(dayofweek from datetime(snapshots.collected_at, systems.timezone)) in (1, 7) as is_weekend,
    snapshots.is_in_service,
    snapshots.bikes_available,
    snapshots.docks_available,
    snapshots.bikes_mechanical,
    snapshots.bikes_electric
from snapshots
inner join {{ ref('systems') }} as systems
    on snapshots.system_id = systems.system_id
