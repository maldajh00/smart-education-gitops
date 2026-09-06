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
  ]
}
