{{ config(
    materialized='incremental',
    incremental_strategy='insert_overwrite',
    partition_by={'field': 'snapshot_date', 'data_type': 'date'},
    cluster_by=['system_id', 'station_key'],
    on_schema_change='fail'
) }}

-- One row per station per snapshot, with shortage flags.

select
    snapshot_key,
    station_key,
    system_id,
    collected_at,
    snapshot_date,
    collected_at_local,
    local_hour,
    is_weekend,
    is_in_service,
    bikes_available,
    docks_available,
    bikes_mechanical,
    bikes_electric,
    bikes_available = 0  as is_empty,   -- no bike to rent
    bikes_available <= 2 as is_low,     -- practically empty
    docks_available = 0  as is_full     -- no dock to return a bike
from {{ ref('int_station_snapshots') }}
{% if is_incremental() %}
where snapshot_date >= date_sub(current_date(), interval {{ var('lookback_days', 2) }} day)
{% endif %}
