{{ config(
    materialized='incremental',
    incremental_strategy='insert_overwrite',
    partition_by={'field': 'snapshot_date', 'data_type': 'date'},
    cluster_by=['station_uid'],
    on_schema_change='fail'
) }}

-- One row per YouBike station per collected snapshot.
-- TDX payload = a JSON array of stations.

with source as (

    select collected_at, payload
    from {{ source('raw', 'youbike_availability') }}
    {% if is_incremental() %}
    -- only reprocess the last 2 days (partition pruning on the raw table)
    where collected_at >= timestamp(date_sub(current_date(), interval {{ var('lookback_days', 2) }} day))
    {% endif %}

),

stations as (

    select
        source.collected_at,
        station
    from source,
        unnest(json_query_array(source.payload)) as station

)

select
    concat(json_value(station.StationUID), '_', format_timestamp('%Y%m%dT%H%M%S', collected_at)) as snapshot_id,
    'youbike_hsinchu'                                                        as system_id,
    json_value(station.StationUID)                                           as station_uid,
    collected_at,
    date(collected_at)                                                       as snapshot_date,
    timestamp(json_value(station.SrcUpdateTime))                             as source_updated_at,
    cast(json_value(station.ServiceStatus) as int64) = 1                     as is_in_service,
    cast(json_value(station.AvailableRentBikes) as int64)                    as bikes_available,
    cast(json_value(station.AvailableReturnBikes) as int64)                  as docks_available,
    cast(json_value(station.AvailableRentBikesDetail.GeneralBikes) as int64) as bikes_mechanical,
    cast(json_value(station.AvailableRentBikesDetail.ElectricBikes) as int64) as bikes_electric
from stations
