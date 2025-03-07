variable "project_id" {
  description = "Google Cloud Project ID"
  type        = string
}

variable "gcs_location" {
  description = "GCS Bucket Location"
  type        = string
  default     = "us-central1"
}
