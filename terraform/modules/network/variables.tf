variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "Region for the subnet, router, and Cloud NAT."
  type        = string
}

variable "network_name" {
  description = "Name of the VPC network."
  type        = string
}

variable "network_description" {
  description = "Description of the VPC network."
  type        = string
  default     = "Production VPC for GKE assessment"
}

variable "subnet_name" {
  description = "Name of the primary GKE subnet."
  type        = string
}

variable "subnet_description" {
  description = "Description of the primary GKE subnet."
  type        = string
  default     = "Primary subnet for GKE regional cluster"
}

variable "subnet_cidr" {
  description = "Primary IP range of the subnet."
  type        = string
}

variable "secondary_ranges" {
  description = <<-EOT
    Named secondary IP ranges on the subnet, keyed by range name.
    The GKE cluster's own auto-provisioned pod range
    (gke-<cluster>-pods-<suffix>) is NOT included here — it is created
    and owned by GKE itself when the cluster is provisioned with
    ip_allocation_policy {} (no explicit range name), not by this
    module. These are the pre-reserved, currently-unused ranges that
    exist on the subnet alongside it.
  EOT
  type        = map(string)
  default     = {}
}

variable "router_name" {
  description = "Name of the Cloud Router used for Cloud NAT."
  type        = string
}

variable "nat_name" {
  description = "Name of the Cloud NAT gateway."
  type        = string
}

variable "enable_flow_logs" {
  description = "Enable VPC flow logs on the primary subnet."
  type        = bool
  default     = true
}

variable "flow_logs_sampling" {
  description = "Flow log sampling rate (0.0-1.0)."
  type        = number
  default     = 0.5
}
