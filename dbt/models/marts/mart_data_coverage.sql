-- Data coverage per system, shown on the dashboard next to every rate.
-- Reads only the collected_at column of the raw tables: almost free.

with snapshots as (

    select 'youbike_hsinchu' as system_id, collected_at
    from {{ source('raw', 'youbike_availability') }}

    union all

    select 'velib_paris', collected_at
    from {{ source('raw', 'velib_station_status') }}

)

select
    snapshots.system_id,
    systems.city,
    datetime(min(snapshots.collected_at), systems.timezone)           as first_snapshot_local,
    datetime(max(snapshots.collected_at), systems.timezone)           as last_snapshot_local,
    count(distinct date(snapshots.collected_at, systems.timezone))    as n_days,
    count(distinct if(
        extract(dayofweek from datetime(snapshots.collected_at, systems.timezone)) not in (1, 7),
        date(snapshots.collected_at, systems.timezone), null))         as n_weekdays,
    count(*)                                                          as n_snapshots
from snapshots
inner join {{ ref('systems') }} as systems
    on snapshots.system_id = systems.system_id
group by snapshots.system_id, systems.city, systems.timezone
