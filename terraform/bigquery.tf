locals {
  raw_tables = [
    "velib_station_status",
    "velib_station_information",
    "youbike_availability",
    "youbike_station",
  ]
}

# One row per raw collector file; JSON parsing happens later in dbt (ELT)
resource "google_bigquery_table" "raw" {
  for_each            = toset(local.raw_tables)
  dataset_id          = google_bigquery_dataset.layers["raw"].dataset_id
  table_id            = each.key
  description         = "One row per raw collector file (JSON payload), loaded hourly by Airflow from GCS."
  deletion_protection = false # rebuildable from GCS with an Airflow backfill

  time_partitioning {
    type  = "DAY"
    field = "collected_at"
  }

  schema = jsonencode([
    { name = "source_file", type = "STRING", mode = "REQUIRED", description = "gs:// URI of the raw file (merge key)" },
    { name = "collected_at", type = "TIMESTAMP", mode = "REQUIRED", description = "Collection time (UTC), from the file name" },
    { name = "loaded_at", type = "TIMESTAMP", mode = "REQUIRED", description = "Load time into BigQuery (UTC)" },
    { name = "payload", type = "JSON", mode = "REQUIRED", description = "API response, as received" },
  ])
}
