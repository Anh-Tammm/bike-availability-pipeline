provider "google" {
  project = var.project_id
  region  = var.region

  # Labels added to every resource: useful to track costs
  default_labels = {
    project    = "bike-pipeline"
    managed_by = "terraform"
  }
}

locals {
  datasets = ["raw", "staging", "marts"]
}

# ---------- Data lake: raw API responses ----------
resource "google_storage_bucket" "raw" {
  name                        = "${var.project_id}-raw"
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # Raw data cannot be re-collected (no official history):
  # refuse to destroy a non-empty bucket
  force_destroy = false

  # After 30 days, move files to a cheaper storage class
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
}

# ---------- Data warehouse: one dataset per layer ----------
resource "google_bigquery_dataset" "layers" {
  for_each   = toset(local.datasets)
  dataset_id = each.key
  location   = var.region
}

# ---------- Pipeline identity (least privilege) ----------
resource "google_service_account" "pipeline" {
  account_id   = "pipeline-runner"
  display_name = "Bike pipeline runner"
}

# Read/write objects in the raw bucket only
resource "google_storage_bucket_iam_member" "pipeline_raw" {
  bucket = google_storage_bucket.raw.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.pipeline.email}"
}

# Read/write tables in our 3 datasets only
resource "google_bigquery_dataset_iam_member" "pipeline_datasets" {
  for_each   = google_bigquery_dataset.layers
  dataset_id = each.value.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.pipeline.email}"
}

# Run BigQuery jobs (queries, loads) in the project
resource "google_project_iam_member" "pipeline_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.pipeline.email}"
}
