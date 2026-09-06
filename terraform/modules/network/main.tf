resource "google_compute_network" "this" {
  project                 = var.project_id
  name                    = var.network_name
  description             = var.network_description
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "gke" {
  project                  = var.project_id
  name                     = var.subnet_name
  description              = var.subnet_description
  region                   = var.region
  network                  = google_compute_network.this.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true
  purpose                  = "PRIVATE"
  stack_type               = "IPV4_ONLY"

  dynamic "secondary_ip_range" {
    for_each = var.secondary_ranges
    content {
      range_name    = secondary_ip_range.key
      ip_cidr_range = secondary_ip_range.value
    }
  }

  dynamic "log_config" {
    for_each = var.enable_flow_logs ? [1] : []
    content {
      aggregation_interval = "INTERVAL_5_SEC"
      flow_sampling        = var.flow_logs_sampling
      metadata             = "INCLUDE_ALL_METADATA"
      filter_expr          = "true"
    }
  }

  lifecycle {
    # GKE adds its own auto-provisioned pod secondary range
    # (gke-<cluster>-pods-<suffix>) to this subnet outside of Terraform,
    # via the cluster's ip_allocation_policy. Don't fight that.
    ignore_changes = [secondary_ip_range]
  }
}

resource "google_compute_router" "nat" {
  project = var.project_id
  name    = var.router_name
  region  = var.region
  network = google_compute_network.this.id

  lifecycle {
    # This router only backs Cloud NAT — it has no real BGP peers, so the
    # API reports a zero-value bgp block (asn 0) that isn't a valid,
    # settable ASN. Declaring `asn = 0` explicitly risks the API
    # rejecting it as an invalid ASN on apply; ignore the block instead
    # of fighting over a field nothing here actually configures.
    ignore_changes = [bgp]
  }
}

resource "google_compute_router_nat" "this" {
  project                            = var.project_id
  name                               = var.nat_name
  router                             = google_compute_router.nat.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ALL"
  }
}
