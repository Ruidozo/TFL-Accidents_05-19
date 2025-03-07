resource "google_storage_bucket" "datalake" {
  name          = "${var.project_id}-datalake"
  location      = var.gcs_location
  storage_class = "STANDARD"

  uniform_bucket_level_access = true

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 365 # Retain objects for 1 year
    }
  }

  versioning {
    enabled = true
  }

  labels = {
    environment = "production"
    purpose     = "data-lake"
  }
}

output "datalake_bucket_name" {
  value = google_storage_bucket.datalake.name
}