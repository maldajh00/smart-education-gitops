# Remote state in GCS. The bucket itself is created once, out-of-band,
# by terraform/bootstrap (a separate, local-state-only root module) —
# see terraform/bootstrap/README.md and terraform/README.md §State.
# There is no chicken-and-egg here: this config's own state cannot live
# in a bucket this same config creates.
terraform {
  backend "gcs" {
    bucket = "smart-education-assignment-tfstate"
    prefix = "prod"
  }
}
