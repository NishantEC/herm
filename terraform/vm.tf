data "google_compute_image" "debian" {
  family  = "debian-12"
  project = "debian-cloud"
}

# startup_script is rendered by cli/commands/up.sh (which inlines each script
# under cloud-init/scripts/ and each systemd unit under systemd/ into a single
# bash script). It is passed in via TF_VAR_startup_script and bound to GCE's
# `startup-script` metadata key, which google-startup-scripts.service executes
# on first boot. We do NOT use cloud-init's `user-data` key because the
# debian-cloud/debian-12 image does not run cloud-init by default.

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

    # Ephemeral external IPv4 for v0.1. The VM needs public internet egress to
    # fetch apt/npm/Tailscale packages on first boot, and we don't ship a Cloud
    # NAT in v0.1 (~$32/mo). The deny-all-ingress firewall (network.tf) blocks
    # all inbound from 0.0.0.0/0, so the public IP carries zero attack surface
    # — connections can be initiated *outbound* only. v0.4 paranoid mode swaps
    # this for Cloud NAT + egress allowlist and removes the external IP.
    access_config {
      network_tier = "STANDARD"
    }
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
    startup-script     = var.startup_script
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
