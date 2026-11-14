# ---------- APIs needed by the cloud collector ----------
resource "google_project_service" "collector_apis" {
  for_each = toset([
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudscheduler.googleapis.com",
  ])
  service            = each.key
  disable_on_destroy = false
}

# ---------- Container registry (Docker images) ----------
resource "google_artifact_registry_repository" "containers" {
  repository_id = "bike-pipeline"
  location      = var.region
  format        = "DOCKER"

  # Keep the 5 most recent images, delete older ones after 30 days
  cleanup_policies {
    id     = "keep-5-most-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = 5
    }
  }
  cleanup_policies {
    id     = "delete-older-than-30d"
    action = "DELETE"
    condition {
      older_than = "2592000s"
    }
  }

  depends_on = [google_project_service.collector_apis]
}

# ---------- Small bucket for pipeline state (TDX token cache) ----------
resource "google_storage_bucket" "state" {
  name                        = "${var.project_id}-state"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true # only holds a cache: safe to delete
}

resource "google_storage_bucket_iam_member" "pipeline_state" {
  bucket = google_storage_bucket.state.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.pipeline.email}"
}

# ---------- Secrets: containers only, values added with gcloud ----------
# (secret values must never appear in Terraform code or state)
resource "google_secret_manager_secret" "tdx" {
  for_each  = toset(["tdx-client-id", "tdx-client-secret"])
  secret_id = each.key

  replication {
    auto {}
  }

  depends_on = [google_project_service.collector_apis]
}

resource "google_secret_manager_secret_iam_member" "pipeline_tdx" {
  for_each  = google_secret_manager_secret.tdx
  secret_id = each.value.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.pipeline.email}"
}
