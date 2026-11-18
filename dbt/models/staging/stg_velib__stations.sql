{{ config(materialized='view') }}

-- Latest known attributes of each Vélib' station (daily GBFS station_information).

with stations as (

    select
        source.collected_at,
        station
    from {{ source('raw', 'velib_station_information') }} as source,
        unnest(json_query_array(source.payload.data.stations)) as station

)

select
    concat('velib_paris:', json_value(station.station_id)) as station_key,
    'velib_paris'                                          as system_id,
    json_value(station.station_id)                         as station_uid,
    json_value(station.name)                               as station_name,
    json_value(station.name)                               as station_name_local,
    cast(json_value(station.lat) as float64)               as latitude,
    cast(json_value(station.lon) as float64)               as longitude,
    cast(json_value(station.capacity) as int64)            as capacity,
    collected_at                                           as last_seen_at
from stations
qualify row_number() over (partition by json_value(station.station_id) order by collected_at desc) = 1
