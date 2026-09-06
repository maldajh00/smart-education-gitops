variable "project_id" {
  type = string
}

variable "region" {
  description = "Region for this regional GKE cluster."
  type        = string
}

variable "cluster_name" {
  type = string
}

variable "network" {
  description = "Self link / ID of the VPC network."
  type        = string
}

variable "subnetwork" {
  description = "Self link / ID of the GKE subnet."
  type        = string
}

variable "release_channel" {
  type    = string
  default = "REGULAR"
}

variable "management_pool" {
  description = "The single-node, publicly-reachable management node pool (ArgoCD, Vault, ESO, Prometheus)."
  type = object({
    name         = string
    machine_type = string
    disk_type    = string
    disk_size_gb = number
    node_count   = number
    zones        = list(string)
    taint_key    = string
    taint_value  = string
    label_key    = string
    label_value  = string
  })
}

variable "application_pool" {
  description = "The private, multi-zone application node pool (backend/frontend/postgres)."
  type = object({
    name         = string
    machine_type = string
    disk_type    = string
    disk_size_gb = number
    node_count   = number
    zones        = list(string)
    label_key    = string
    label_value  = string
  })
}
