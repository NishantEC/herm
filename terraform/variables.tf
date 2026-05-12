variable "project_id" {
  type        = string
  description = "GCP project to deploy into."
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

variable "machine_type" {
  type        = string
  default     = "e2-small"
  description = "VM machine type. Locked to e2-small to bound cost; override at your own risk."

  validation {
    condition     = contains(["e2-micro", "e2-small", "e2-medium"], var.machine_type)
    error_message = "machine_type must be one of e2-micro, e2-small, e2-medium."
  }
}

variable "disk_size_gb" {
  type    = number
  default = 10

  validation {
    condition     = var.disk_size_gb >= 10 && var.disk_size_gb <= 100
    error_message = "disk_size_gb must be between 10 and 100."
  }
}

variable "hostname" {
  type    = string
  default = "herm-vm"
}

variable "tailnet_owner_tag" {
  type        = string
  description = "Tailscale ACL tag (e.g. tag:nishant) authorized to reach the VM."

  validation {
    condition     = can(regex("^tag:[a-z0-9-]+$", var.tailnet_owner_tag))
    error_message = "tailnet_owner_tag must look like tag:<lowercase-name>."
  }
}

variable "tailscale_auth_key" {
  type        = string
  sensitive   = true
  description = "Single-use ephemeral Tailscale auth key. Stored in Secret Manager."
}

variable "budget_monthly_usd" {
  type    = number
  default = 25
}
