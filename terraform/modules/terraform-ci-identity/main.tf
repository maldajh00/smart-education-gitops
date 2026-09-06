# WIF identities for THIS repo's (smart-education-gitops) own Terraform
# CI. Reuses the existing github-actions-pool (created by the
# ci-identity module for the application repo) rather than a second
# pool, but gets its own provider — scoped, via attribute_condition, to
# this repo only — and its own two service accounts, so plan and apply
# hold different privilege levels and neither is the app repo's image-
# push identity.
resource "google_iam_workload_identity_pool_provider" "gitops" {
  project                            = var.project_id
  workload_identity_pool_id          = var.pool_id
  workload_identity_pool_provider_id = var.provider_id
  display_name                       = "GitOps Repo Terraform CI"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
  }

  attribute_condition = "assertion.repository == '${var.github_repository}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# ---------------------------------------------------------------------
# Plan: read-only. Used on every PR; never grants write access to
# anything.
# ---------------------------------------------------------------------
resource "google_service_account" "plan" {
  project      = var.project_id
  account_id   = var.plan_service_account_id
  display_name = "Terraform plan (read-only)"
}

resource "google_service_account_iam_member" "plan_wif" {
  service_account_id = google_service_account.plan.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${var.pool_name}/attribute.repository/${var.github_repository}"
}

resource "google_project_iam_member" "plan_viewer" {
  project = var.project_id
  role    = "roles/viewer"
  member  = "serviceAccount:${google_service_account.plan.email}"
}

# roles/viewer does not cover the GCS backend's own object read/list
# calls — `terraform init`/`plan` need this bucket-scoped grant
# regardless.
resource "google_storage_bucket_iam_member" "plan_state_read" {
  bucket = var.state_bucket_name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.plan.email}"
}

# ---------------------------------------------------------------------
# Apply: only runs behind the terraform-prod GitHub Environment's
# required-reviewer gate (see .github/workflows/terraform.yaml). Granted
# exactly the resource-type roles this config manages — not
# Editor/Owner.
# ---------------------------------------------------------------------
resource "google_service_account" "apply" {
  project      = var.project_id
  account_id   = var.apply_service_account_id
  display_name = "Terraform apply"
}

resource "google_service_account_iam_member" "apply_wif" {
  service_account_id = google_service_account.apply.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${var.pool_name}/attribute.repository/${var.github_repository}"
}

resource "google_project_iam_member" "apply_roles" {
  for_each = toset(var.apply_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.apply.email}"
}

# apply needs to read AND write state objects (including the lock
# object) — objectAdmin, scoped to just this bucket, not project-wide
# storage access.
resource "google_storage_bucket_iam_member" "apply_state_readwrite" {
  bucket = var.state_bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.apply.email}"
}
