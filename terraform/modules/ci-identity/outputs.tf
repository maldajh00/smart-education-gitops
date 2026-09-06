output "service_account_email" {
  value = google_service_account.github_actions.email
}

output "workload_identity_provider" {
  description = "Full resource name to pass as workload_identity_provider in google-github-actions/auth."
  value       = google_iam_workload_identity_pool_provider.github.name
}
