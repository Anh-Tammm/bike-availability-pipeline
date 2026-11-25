variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "Region for GCS bucket and BigQuery datasets (must match)"
  type        = string
  default     = "europe-west1"
}

variable "github_repository" {
  description = "GitHub repository allowed to deploy (owner/name)"
  type        = string
  default     = "Anh-Tammm/bike-availability-pipeline"
}

variable "alert_email" {
  description = "Email address that receives pipeline alerts"
  type        = string
}