variable "project_id" {
  type = string
}

variable "pool_id" {
  description = "Workload identity pool ID to add this provider to (reuse the existing github-actions-pool rather than creating a second pool)."
  type        = string
}

variable "pool_name" {
  description = "Full resource name of that pool, for the principalSet member string."
  type        = string
}

variable "provider_id" {
  type    = string
  default = "gitops-provider"
}

variable "github_repository" {
  description = "The gitops repo (owner/name) allowed to mint tokens via this provider."
  type        = string
}

variable "plan_service_account_id" {
  type    = string
  default = "terraform-plan-gsa"
}

variable "apply_service_account_id" {
  type    = string
  default = "terraform-apply-gsa"
}

variable "apply_roles" {
  description = "Project-level roles granted to the apply identity — the specific resource types this Terraform config manages, not Editor/Owner."
  type        = list(string)
  default = [
    "roles/compute.networkAdmin",
    "roles/container.admin",
    "roles/artifactregistry.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.workloadIdentityPoolAdmin",
    # This config manages google_project_iam_member/
    # google_service_account_iam_member resources (ci-identity's WIF
    # binding, artifact-registry's writer binding, this module's own
    # role grants) — reading and setting project-level IAM policy is a
    # distinct permission from any resource-type-admin role above.
    "roles/resourcemanager.projectIamAdmin",
  ]
}

variable "state_bucket_name" {
  description = <<-EOT
    The GCS bucket backing environments/prod's remote state (created by
    terraform/bootstrap, not this module). Both CI identities need
    bucket-scoped access to it — a separate grant from apply_roles,
    since GCS backend access isn't covered by any project-level
    compute/container/registry/IAM role.
  EOT
  type        = string
  default     = "smart-education-assignment-tfstate"
}
