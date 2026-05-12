resource "google_compute_network" "herm" {
  name                    = "herm-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "herm" {
  name          = "herm-subnet"
  ip_cidr_range = "10.42.0.0/24"
  region        = var.region
  network       = google_compute_network.herm.id

  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Default-deny ingress: any rules we add must be explicit.
# (Default VPC has implicit deny-all-ingress anyway; this is belt-and-suspenders.)
resource "google_compute_firewall" "deny_all_ingress" {
  name      = "herm-deny-all-ingress"
  network   = google_compute_network.herm.name
  direction = "INGRESS"
  priority  = 65534

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]
}

# Allow IAP SSH so the owner can `gcloud compute ssh --tunnel-through-iap` for
# break-glass access if Tailscale itself is broken on the VM.
resource "google_compute_firewall" "iap_ssh" {
  name      = "herm-allow-iap-ssh"
  network   = google_compute_network.herm.name
  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # IAP TCP forwarding range.
  source_ranges = ["35.235.240.0/20"]
}
