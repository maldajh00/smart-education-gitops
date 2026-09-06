# No credentials configured here. Locally, gcloud Application Default
# Credentials are used (`gcloud auth application-default login`). In CI,
# see modules/ci-identity and .github/workflows/terraform.yaml — the
# runner authenticates via Workload Identity Federation, never a
# service-account JSON key.
provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}
