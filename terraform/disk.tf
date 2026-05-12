resource "google_compute_disk" "herm" {
  name = "herm-data"
  type = "pd-ssd"
  size = var.disk_size_gb
  zone = var.zone

  labels = {
    managed-by = "herm"
  }

  lifecycle {
    # The whole point: surviving `herm down`.
    prevent_destroy = true
  }
}
