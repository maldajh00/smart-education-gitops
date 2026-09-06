# One-time bootstrap: creates the GCS bucket that holds every other
# Terraform root's remote state. This root's OWN state is local
# (terraform.tfstate, gitignored) — it cannot use the GCS backend it is
# itself creating. Run this once per project; after the bucket exists,
# nobody needs to touch this directory again except to change the
# bucket's own settings (versioning, retention, location).
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.9"
    }
  }
}

variable "project_id" {
  type    = string
  default = "smart-education-assignment"
}

variable "region" {
  type    = string
  default = "me-central1"
}

variable "state_bucket_name" {
  type    = string
  default = "smart-education-assignment-tfstate"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_storage_bucket" "tfstate" {
  project  = var.project_id
  name     = var.state_bucket_name
  location = var.region

  # Object versioning lets a bad apply's prior state be recovered without
  # a separate backup process.
  versioning {
    enabled = true
  }

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # Old state versions accumulate forever otherwise.
  lifecycle_rule {
    condition {
      num_newer_versions = 20
    }
    action {
      type = "Delete"
    }
  }
}
