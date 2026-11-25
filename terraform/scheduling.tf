locals {
  collector_image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.containers.repository_id}/collector:latest"

  # One Cloud Run job, three triggers with different arguments (3 jobs = Cloud Scheduler free tier)
  schedules = {
    velib-status = {
      schedule = "*/5 * * * *"
      args     = ["gbfs_collector.py", "--system", "velib", "--feeds", "station_status"]
    }
    youbike-availability = {
      schedule = "*/20 * * * *" # 72 calls/day, within the TDX free quota
      args     = ["tdx_collector.py", "--feeds", "availability"]
    }
    daily-reference = {
      schedule = "30 4 * * *"
      args     = ["run_daily.py"]
    }
  }
}

# ---------- The job: runs the collector container ----------
resource "google_cloud_run_v2_job" "collector" {
  name                = "collector"
  location            = var.region
  deletion_protection = false

  template {
    task_count = 1

    template {
      service_account = google_service_account.pipeline.email
      timeout         = "300s"
      max_retries     = 1

      containers {
        image = local.collector_image
        args  = local.schedules["velib-status"].args # default; overridden by each trigger

        resources {
          limits = {
            cpu    = "1"
            memory = "512Mi"
          }
        }

        env {
          name  = "GCP_PROJECT_ID"
          value = var.project_id
        }
        env {
          name  = "GCS_BUCKET"
          value = google_storage_bucket.raw.name
        }
        env {
          name  = "TDX_TOKEN_CACHE"
          value = "gs://${google_storage_bucket.state.name}/tdx_token.json"
        }
        env {
          name = "TDX_CLIENT_ID"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.tdx["tdx-client-id"].secret_id
              version = "latest"
            }
          }
        }
        env {
          name = "TDX_CLIENT_SECRET"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.tdx["tdx-client-secret"].secret_id
              version = "latest"
            }
          }
        }
      }
    }
  }

  depends_on = [google_secret_manager_secret_iam_member.pipeline_tdx]
  # Terraform owns the job; the CD pipeline owns the image version
  lifecycle {
    ignore_changes = [
      template[0].template[0].containers[0].image,
      client,
      client_version,
    ]
  }
}

# ---------- Identity used by Cloud Scheduler to start the job ----------
resource "google_service_account" "scheduler" {
  account_id   = "collector-scheduler"
  display_name = "Cloud Scheduler trigger for the collector job"
}

# Starting a job WITH argument overrides requires run.jobs.runWithOverrides,
# included in roles/run.developer (not in roles/run.invoker). Granted on this job only.
resource "google_cloud_run_v2_job_iam_member" "scheduler_run" {
  name     = google_cloud_run_v2_job.collector.name
  location = var.region
  role     = "roles/run.developer"
  member   = "serviceAccount:${google_service_account.scheduler.email}"
}

# ---------- The three triggers ----------
resource "google_cloud_scheduler_job" "collector" {
  for_each  = local.schedules
  name      = each.key
  region    = var.region
  schedule  = each.value.schedule
  time_zone = "Asia/Taipei"

  retry_config {
    retry_count = 0 # no retry: the next run is only minutes away
  }

  http_target {
    http_method = "POST"
    uri         = "https://run.googleapis.com/v2/projects/${var.project_id}/locations/${var.region}/jobs/${google_cloud_run_v2_job.collector.name}:run"
    headers     = { "Content-Type" = "application/json" }
    body = base64encode(jsonencode({
      overrides = {
        containerOverrides = [{ args = each.value.args }]
      }
    }))

    oauth_token {
      service_account_email = google_service_account.scheduler.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  depends_on = [google_cloud_run_v2_job_iam_member.scheduler_run]
}
