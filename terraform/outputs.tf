output "vm_name" {
  value = google_compute_instance.herm.name
}

output "vm_internal_ip" {
  value = google_compute_instance.herm.network_interface[0].network_ip
}

output "vm_zone" {
  value = google_compute_instance.herm.zone
}

output "backup_bucket" {
  value = google_storage_bucket.backup.name
}

output "service_account_email" {
  value = google_service_account.herm_vm.email
}

output "tailnet_hostname" {
  value = var.hostname
}
