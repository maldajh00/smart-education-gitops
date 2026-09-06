resource "google_artifact_registry_repository" "this" {
  project       = var.project_id
  location      = var.region
  repository_id = var.repository_id
  description   = var.description
  format        = "DOCKER"
  mode          = "STANDARD_REPOSITORY"
}

# Repository-scoped IAM only — deliberately not a project-level role.
# CI's identity (see modules/ci-identity) can push images here and
# nowhere else.
resource "google_artifact_registry_repository_iam_member" "writers" {
  for_each = toset(var.writer_members)

  project    = var.project_id
  location   = google_artifact_registry_repository.this.location
  repository = google_artifact_registry_repository.this.repository_id
  role       = "roles/artifactregistry.writer"
  member     = each.value
}
