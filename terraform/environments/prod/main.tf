# Production environment: wires the network, GKE, Artifact Registry, and
# CI identity modules together with the values that match the already-
# running infrastructure (see README.md at the repo terraform/ root for
# the discovery commands used and the import plan).

module "network" {
  source = "../../modules/network"

  project_id   = var.project_id
  region       = var.region
  network_name = "prod-vpc"
  subnet_name  = "gke-prod-subnet"
  subnet_cidr  = "10.10.0.0/20"

  # Pre-reserved secondary ranges on the subnet. Neither is currently
  # consumed by the cluster (GKE auto-provisioned its own pod range
  # instead — see modules/network's ip_allocation_policy comment), but
  # both exist on the live subnet and must stay represented so
  # `terraform plan` doesn't try to remove them.
  secondary_ranges = {
    gke-pods     = "10.20.0.0/16"
    gke-services = "10.30.0.0/20"
  }

  router_name = "prod-router"
  nat_name    = "prod-nat"
}

module "gke" {
  source = "../../modules/gke"

  project_id   = var.project_id
  region       = var.region
  cluster_name = "prod-gke"
  network      = module.network.network_id
  subnetwork   = module.network.subnet_id

  management_pool = {
    name         = "management-pool"
    machine_type = "e2-medium"
    disk_type    = "pd-standard"
    disk_size_gb = 50
    node_count   = 1
    zones        = ["me-central1-b"]
    taint_key    = "workload"
    taint_value  = "management"
    label_key    = "workload"
    label_value  = "management"
  }

  application_pool = {
    name         = "application-pool"
    machine_type = "e2-standard-2"
    disk_type    = "pd-balanced"
    disk_size_gb = 50
    node_count   = 1
    zones        = ["me-central1-a", "me-central1-b", "me-central1-c"]
    label_key    = "workload"
    label_value  = "application"
  }
}

module "artifact_registry" {
  source = "../../modules/artifact-registry"

  project_id    = var.project_id
  region        = var.region
  repository_id = "prod-gke-repo"

  writer_members = [
    "serviceAccount:${module.ci_identity.service_account_email}",
  ]
}

module "ci_identity" {
  source = "../../modules/ci-identity"

  project_id        = var.project_id
  github_repository = "maldajh00/smart-education-assessment"
}

# This repo's (smart-education-gitops) own Terraform CI identity — a
# separate provider on the same pool, and separate plan/apply service
# accounts from the app repo's image-push identity above.
module "terraform_ci_identity" {
  source = "../../modules/terraform-ci-identity"

  project_id        = var.project_id
  pool_id           = module.ci_identity.pool_id
  pool_name         = module.ci_identity.pool_name
  github_repository = "maldajh00/smart-education-gitops"
}
