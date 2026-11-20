-- One row per station x day type (weekday/weekend) x local hour.
-- Stores additive counts (not only percentages) so the dashboard can re-aggregate correctly:
-- rate = SUM(n_empty) / SUM(n_snapshots), never AVG(pct_empty).

select
    facts.station_key,
    stations.display_name,
    stations.system_id,
    stations.city,
    stations.is_focus,
    case
        when stations.is_focus then 'NYCU campus'
        when stations.city = 'Hsinchu' then 'Hsinchu (other stations)'
        else stations.city
    end                                         as station_group,
    stations.latitude,
    stations.longitude,
    concat(cast(stations.latitude as string), ',', cast(stations.longitude as string)) as lat_lon,
    stations.capacity,
    if(facts.is_weekend, 'weekend', 'weekday')  as day_type,
    facts.local_hour,
    count(distinct facts.snapshot_date)         as n_days,
    count(*)                                    as n_snapshots,
    countif(facts.is_empty)                     as n_empty,
    countif(facts.is_low)                       as n_low,
    countif(facts.is_full)                      as n_full,
    round(avg(facts.bikes_available), 1)        as avg_bikes_available,
    round(safe_divide(countif(facts.is_empty), count(*)), 4) as pct_empty,
    round(safe_divide(countif(facts.is_low), count(*)), 4)   as pct_low
from {{ ref('fct_station_snapshots') }} as facts
inner join {{ ref('dim_stations') }} as stations
    on facts.station_key = stations.station_key
where facts.is_in_service
group by all
