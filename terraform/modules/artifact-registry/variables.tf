variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "repository_id" {
  type = string
}

variable "description" {
  type    = string
  default = "Production GKE container images"
}

variable "writer_members" {
  description = "IAM members granted roles/artifactregistry.writer on this repository only (least privilege — not project-wide)."
  type        = list(string)
  default     = []
}
