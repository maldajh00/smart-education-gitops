locals {
  common_labels = {
    environment = var.environment
    managed-by  = "terraform"
    project     = "smart-education"
  }
}
