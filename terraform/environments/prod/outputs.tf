output "gke_cluster_name" {
  value = module.gke.cluster_name
}

output "gke_workload_identity_pool" {
  value = module.gke.workload_identity_pool
}

output "artifact_registry_repository_url" {
  value = module.artifact_registry.repository_url
}

output "ci_service_account_email" {
  value = module.ci_identity.service_account_email
}

output "ci_workload_identity_provider" {
  description = "Pass this as workload_identity_provider in google-github-actions/auth (app repo's CI)."
  value       = module.ci_identity.workload_identity_provider
}

output "terraform_ci_workload_identity_provider" {
  description = "Set as the TF_WORKLOAD_IDENTITY_PROVIDER repository variable on smart-education-gitops."
  value       = module.terraform_ci_identity.workload_identity_provider
}

output "terraform_plan_service_account_email" {
  description = "Set as the TF_PLAN_SERVICE_ACCOUNT repository variable."
  value       = module.terraform_ci_identity.plan_service_account_email
}

output "terraform_apply_service_account_email" {
  description = "Set as the TF_APPLY_SERVICE_ACCOUNT repository variable."
  value       = module.terraform_ci_identity.apply_service_account_email
}

output "network_name" {
  value = module.network.network_name
}

output "subnet_name" {
  value = module.network.subnet_name
}
