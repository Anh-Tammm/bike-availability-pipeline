output "raw_bucket" {
  value = google_storage_bucket.raw.name
}

output "datasets" {
  value = [for d in google_bigquery_dataset.layers : d.dataset_id]
}

output "pipeline_service_account" {
  value = google_service_account.pipeline.email
}
