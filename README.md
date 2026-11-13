# Bike Availability Pipeline

Batch data pipeline collecting real-time bike-sharing station availability
to analyze station shortages by hour and day of week.

**Status:** 🚧 Work in progress

## Data sources
- Vélib' Métropole (Paris), GBFS feed. License: _to be completed_
- YouBike 2.0 Hsinchu (Taiwan), via TDX / MOTC. _Planned_

## Architecture
Terraform · GCS · BigQuery · Airflow · dbt · Looker Studio · Snowflake (secondary target)

## Repository structure
| Folder | Content |
|---|---|
| `terraform/` | Cloud infrastructure (GCS, BigQuery, IAM) |
| `ingestion/` | Python collectors, one per source |
| `orchestration/` | Airflow DAGs |
| `dbt/` | Transformations: staging → intermediate → marts |
| `docs/` | Architecture diagrams, notes |
