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
  description = "Pass this as workload_identity_provider in google-github-actions/auth."
  value       = module.ci_identity.workload_identity_provider
}

output "network_name" {
  value = module.network.network_name
}

output "subnet_name" {
  value = module.network.subnet_name
}
