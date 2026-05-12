resource "google_secret_manager_secret" "tailscale_auth_key" {
  secret_id = "herm-tailscale-auth-key"

  replication {
    auto {}
  }

  # Short rotation reminder — owner sees a console warning if this secret lives long.
  ttl = "604800s" # 7 days; the secret should be deleted by cloud-init within minutes.
}

resource "google_secret_manager_secret_version" "tailscale_auth_key" {
  secret      = google_secret_manager_secret.tailscale_auth_key.id
  secret_data = var.tailscale_auth_key
}
