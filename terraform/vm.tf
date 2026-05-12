data "google_compute_image" "debian" {
  family  = "debian-12"
  project = "debian-cloud"
}

# cloud_init_user_data is rendered by cli/commands/up.sh (which inlines the
# base64-encoded scripts and systemd units) and passed in via TF_VAR. Reading
# the cloud-init/cloud-init.yaml template here directly would leave the
# BASE64_* placeholders literal and silently break cloud-init on first boot.

resource "google_compute_instance" "herm" {
  name         = var.hostname
  machine_type = var.machine_type
  zone         = var.zone

  tags = ["herm"]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian.self_link
      size  = 10
      type  = "pd-balanced"
    }
  }

  attached_disk {
    source      = google_compute_disk.herm.self_link
    device_name = "herm-data"
    mode        = "READ_WRITE"
  }

  network_interface {
    subnetwork = google_compute_subnetwork.herm.self_link
    # No access_config block ⇒ no external IP. This is load-bearing.
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  service_account {
    email  = google_service_account.herm_vm.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin     = "TRUE"
    user-data          = var.cloud_init_user_data
    herm-project-id    = var.project_id
    herm-ts-secret-id  = google_secret_manager_secret.tailscale_auth_key.secret_id
    herm-backup-bucket = google_storage_bucket.backup.name
  }

  allow_stopping_for_update = true

  depends_on = [
    google_secret_manager_secret_version.tailscale_auth_key,
    google_secret_manager_secret_iam_member.ts_authkey_reader,
    google_secret_manager_secret_iam_member.ts_authkey_admin,
    google_storage_bucket_iam_member.backup_writer,
  ]
}
