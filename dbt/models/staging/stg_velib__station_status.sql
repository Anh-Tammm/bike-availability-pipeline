{{ config(
    materialized='incremental',
    incremental_strategy='insert_overwrite',
    partition_by={'field': 'snapshot_date', 'data_type': 'date'},
    cluster_by=['station_uid'],
    on_schema_change='fail'
) }}

-- One row per Vélib' station per collected snapshot.
-- GBFS payload = {"data": {"stations": [...]}}; Vélib' adds non-standard camelCase duplicates, ignored here.

with source as (

    select collected_at, payload
    from {{ source('raw', 'velib_station_status') }}
    {% if is_incremental() %}
    where collected_at >= timestamp(date_sub(current_date(), interval 2 day))
    {% endif %}

),

stations as (

    select
        source.collected_at,
        station
    from source,
        unnest(json_query_array(source.payload.data.stations)) as station

)

select
    concat(json_value(station.station_id), '_', format_timestamp('%Y%m%dT%H%M%S', collected_at)) as snapshot_id,
    'velib_paris'                                                     as system_id,
    json_value(station.station_id)                                    as station_uid,
    collected_at,
    date(collected_at)                                                as snapshot_date,
    timestamp_seconds(cast(json_value(station.last_reported) as int64)) as source_updated_at,
    cast(json_value(station.is_installed) as int64) = 1
        and cast(json_value(station.is_renting) as int64) = 1         as is_in_service,
    cast(json_value(station.num_bikes_available) as int64)            as bikes_available,
    cast(json_value(station.num_docks_available) as int64)            as docks_available,
    -- num_bikes_available_types = [{"mechanical": 2}, {"ebike": 14}]: one key per object
    (select sum(cast(json_value(t.mechanical) as int64))
       from unnest(json_query_array(station.num_bikes_available_types)) as t) as bikes_mechanical,
    (select sum(cast(json_value(t.ebike) as int64))
       from unnest(json_query_array(station.num_bikes_available_types)) as t) as bikes_electric
from stations
