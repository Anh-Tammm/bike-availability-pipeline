-- Every raw file of the last 14 days must appear as a snapshot downstream.
-- If this fails after a long outage, run: dbt build --vars '{lookback_days: N}'
with raw_files as (

    select 'youbike_hsinchu' as system_id, collected_at
    from {{ source('raw', 'youbike_availability') }}
    where collected_at >= timestamp(date_sub(current_date(), interval 14 day))

    union all

    select 'velib_paris', collected_at
    from {{ source('raw', 'velib_station_status') }}
    where collected_at >= timestamp(date_sub(current_date(), interval 14 day))

),

staged as (

    select distinct system_id, collected_at
    from {{ ref('fct_station_snapshots') }}
    where snapshot_date >= date_sub(current_date(), interval 14 day)

)

select raw_files.system_id, raw_files.collected_at
from raw_files
left join staged
    on raw_files.system_id = staged.system_id
   and raw_files.collected_at = staged.collected_at
where staged.collected_at is null
