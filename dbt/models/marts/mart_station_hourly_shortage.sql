-- One row per station x day type (weekday/weekend) x local hour.
-- Stores additive counts (not only percentages) so the dashboard can re-aggregate correctly.

select
    facts.station_key,
    stations.display_name,
    stations.system_id,
    stations.city,
    stations.is_focus,
    stations.latitude,
    stations.longitude,
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
