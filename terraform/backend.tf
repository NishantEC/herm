# Backend bucket is created by `herm init` BEFORE the first `terraform apply`.
# It is parameterized at `terraform init -backend-config=...` time so multiple
# owners can run herm in their own projects without collision.

terraform {
  backend "gcs" {
    # bucket configured via: terraform init -backend-config="bucket=${project_id}-herm-tfstate"
    prefix = "v0.1"
  }
}
