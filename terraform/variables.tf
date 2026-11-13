variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "Region for GCS bucket and BigQuery datasets (must match)"
  type        = string
  default     = "europe-west1"
}
