output "repository_id" {
  value = google_artifact_registry_repository.this.repository_id
}

output "host" {
  description = "Artifact Registry Docker host, e.g. me-central1-docker.pkg.dev."
  value       = "${google_artifact_registry_repository.this.location}-docker.pkg.dev"
}

output "repository_url" {
  value = "${google_artifact_registry_repository.this.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.this.repository_id}"
}
