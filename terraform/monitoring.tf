# ---------- Alerting: email when a collector run fails ----------

resource "google_project_service" "monitoring" {
  service            = "monitoring.googleapis.com"
  disable_on_destroy = false
}

resource "google_monitoring_notification_channel" "email" {
  display_name = "Pipeline alerts (email)"
  type         = "email"
  labels = {
    email_address = var.alert_email
  }
  depends_on = [google_project_service.monitoring]
}

# Log-based alert: Cloud Run writes "Container called exit(N)." when a task ends;
# any non-zero code means the collection failed.
resource "google_monitoring_alert_policy" "collector_failed" {
  display_name = "Collector run failed"
  combiner     = "OR"

  conditions {
    display_name = "A collector execution exited with an error"
    condition_matched_log {
      filter = <<-EOT
        resource.type="cloud_run_job"
        resource.labels.job_name="${google_cloud_run_v2_job.collector.name}"
        textPayload:"Container called exit("
        NOT textPayload:"exit(0)"
      EOT
    }
  }

  alert_strategy {
    notification_rate_limit {
      period = "3600s" # at most one email per hour, even during a long outage
    }
    auto_close = "1800s"
  }

  notification_channels = [google_monitoring_notification_channel.email.id]

  documentation {
    mime_type = "text/markdown"
    content   = <<-EOT
      A collector run failed.
      1. `gcloud run jobs executions list --job collector --region europe-west1 --limit 10`
      2. Read the logs of the failed execution (the error message includes the start of the API response).
    EOT
  }
}