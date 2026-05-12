resource "google_service_account" "herm_vm" {
  account_id   = "herm-vm"
  display_name = "herm VM service account"
  description  = "Scoped service account for the herm Compute Engine instance."
}

# Allow the VM SA to read the Tailscale auth key secret.
resource "google_secret_manager_secret_iam_member" "ts_authkey_reader" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.tailscale_auth_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.herm_vm.email}"
}

# Allow the VM SA to delete the secret entry after first-boot tailnet join.
# (deletion of the SECRET, not the version — limits blast radius even if leaked.)
resource "google_secret_manager_secret_iam_member" "ts_authkey_admin" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.tailscale_auth_key.secret_id
  role      = "roles/secretmanager.admin"
  member    = "serviceAccount:${google_service_account.herm_vm.email}"
}

# Allow the VM SA to write backups to the GCS bucket.
resource "google_storage_bucket_iam_member" "backup_writer" {
  bucket = google_storage_bucket.backup.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.herm_vm.email}"
}

# Allow the VM SA to write logs.
resource "google_project_iam_member" "log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.herm_vm.email}"
}
