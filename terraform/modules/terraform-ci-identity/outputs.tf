output "workload_identity_provider" {
  value = google_iam_workload_identity_pool_provider.gitops.name
}

output "plan_service_account_email" {
  value = google_service_account.plan.email
}

output "apply_service_account_email" {
  value = google_service_account.apply.email
}
