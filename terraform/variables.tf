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

variable "tailscale_auth_key" {
  type        = string
  sensitive   = true
  description = "Single-use ephemeral Tailscale auth key. Stored in Secret Manager."
}

variable "cloud_init_user_data" {
  type        = string
  description = "Rendered cloud-init YAML for the VM. Populated by cli/commands/up.sh via TF_VAR_cloud_init_user_data (it inlines base64-encoded scripts + systemd units from cloud-init/scripts/ and systemd/)."
}

# Tailscale ACL tag and monthly budget live in ~/.config/herm/config.toml and
# are applied via the Tailscale admin console + `gcloud billing budgets`, not
# via Terraform. Don't declare them as Terraform variables — tflint flags them
# as unused.
