{{ config(materialized='view') }}

-- Latest known attributes of each YouBike Hsinchu station (daily station list).

with stations as (

    select
        source.collected_at,
        station
    from {{ source('raw', 'youbike_station') }} as source,
        unnest(json_query_array(source.payload)) as station

)

select
    concat('youbike_hsinchu:', json_value(station.StationUID))               as station_key,
    'youbike_hsinchu'                                                        as system_id,
    json_value(station.StationUID)                                           as station_uid,
    regexp_replace(json_value(station.StationName.En), r'^YouBike2\.0_', '')  as station_name,
    regexp_replace(json_value(station.StationName.Zh_tw), r'^YouBike2\.0_', '') as station_name_local,
    cast(json_value(station.StationPosition.PositionLat) as float64)         as latitude,
    cast(json_value(station.StationPosition.PositionLon) as float64)         as longitude,
    cast(json_value(station.BikesCapacity) as int64)                         as capacity,
    collected_at                                                             as last_seen_at
from stations
qualify row_number() over (partition by json_value(station.StationUID) order by collected_at desc) = 1
