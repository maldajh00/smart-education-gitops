variable "project_id" {
  type = string
}

variable "pool_id" {
  type    = string
  default = "github-actions-pool"
}

variable "provider_id" {
  type    = string
  default = "github-provider"
}

variable "service_account_id" {
  type    = string
  default = "github-actions-gsa"
}

variable "github_repository" {
  description = "The single GitHub repo (owner/name) allowed to mint tokens for this identity. Kept as a hard attribute_condition, not a project-wide grant."
  type        = string
}
