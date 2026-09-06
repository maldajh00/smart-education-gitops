variable "project_id" {
  description = "GCP project ID."
  type        = string
  default     = "smart-education-assignment"
}

variable "region" {
  description = "Primary GCP region."
  type        = string
  default     = "me-central1"
}

variable "environment" {
  description = "Environment name, used for labeling."
  type        = string
  default     = "prod"
}
