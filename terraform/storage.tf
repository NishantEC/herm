resource "google_storage_bucket" "backup" {
  name                        = "${var.project_id}-herm-backups"
  location                    = var.region
  force_destroy               = false # `herm nuke` sets this true via a follow-up apply.
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age                = 30
      num_newer_versions = 5
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  # No bucket-level logging block in v0.1: GCS forbids a bucket logging to
  # itself, and provisioning a separate log bucket is a v0.4 task. Project-
  # level Cloud Audit Logs already capture data-access events.
}
