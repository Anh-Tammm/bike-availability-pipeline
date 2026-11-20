# Dashboard (Looker Studio)

Pages: NYCU, Stations NYCU, Calendrier, Paris (screenshots in `img/`).

## Data sources (cache: 12 h)
- `marts.mart_station_hourly_shortage`: station x day type x local hour
- `marts.mart_data_coverage`: period covered and sample size per system
- `marts.mart_focus_station_timeseries`: NYCU stations, one row per snapshot (~20 min)

## Calculated fields
| Field | Formula |
|---|---|
| Taux vide | `SUM(n_empty) / SUM(n_snapshots)` |
| Taux presque vide | `SUM(n_low) / SUM(n_snapshots)` |
| Taux plein | `SUM(n_full) / SUM(n_snapshots)` |
| Taux de remplissage | `SUM(sum_bikes_available) / SUM(sum_capacity)` |
| Vélos moyens par station | `SUM(sum_bikes_available) / SUM(n_snapshots)` |
| Nombre de stations | `COUNT_DISTINCT(station_key)` |
| Type de jour | `CASE WHEN day_type = "weekday" THEN "Semaine" ELSE "Week-end" END` |
| Heure (timeseries source) | `FORMAT_DATETIME("%H:%M", collected_at_local)` |

Rates are re-aggregated from additive counts: never average `pct_empty` or `avg_bikes_available`.

## Field settings
- `local_hour`: Number. `lat_lon`: Geo > Latitude, Longitude. `local_date`: Date.
- Default aggregation `Max` for non-additive attributes repeated on each row: `capacity`, `n_days`.
