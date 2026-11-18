-- Singular test: an empty station is also "low", and counts can't exceed snapshots.
select *
from {{ ref('mart_station_hourly_shortage') }}
where n_empty > n_low
   or n_low > n_snapshots
   or n_full > n_snapshots
