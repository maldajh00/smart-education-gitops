# Regional Standard GKE cluster. Node pools are managed as separate
# google_container_node_pool resources (remove_default_node_pool = true)
# so the management and application pools can each be sized/scaled
# independently, matching the two pools that already exist.
resource "google_container_cluster" "this" {
  project  = var.project_id
  name     = var.cluster_name
  location = var.region

  network    = var.network
  subnetwork = var.subnetwork

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    # No explicit range names: GKE auto-provisions its own pod secondary
    # range on the subnet (matches the live gke-prod-gke-pods-<suffix>
    # range) and its own services range, rather than consuming the
    # network module's pre-reserved (currently unused) secondary ranges.
  }

  release_channel {
    channel = var.release_channel
  }

  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
  }

  # DELIBERATELY not declared: this cluster's live
  # masterAuthorizedNetworksConfig has NO `enabled` field set at all (the
  # authorized-networks restriction feature itself is off — that's a
  # different state than "enabled=true with an empty CIDR allowlist").
  # Declaring this block at all — even just to set
  # gcp_public_cidrs_access_enabled — makes the provider set enabled=true,
  # which blocks every public IP, including admin kubectl/ArgoCD-CLI
  # access, since no CIDR would be allowlisted. Confirmed the hard way:
  # applying this block cut off cluster access mid-import and had to be
  # reverted with `gcloud container clusters update
  # --no-enable-master-authorized-networks`. If authorized networks are
  # ever genuinely wanted, this block must ship together with the real
  # cidr_blocks allowlist in the same change, never alone.

  addons_config {
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }

  monitoring_config {
    enable_components = [
      "SYSTEM_COMPONENTS", "STORAGE", "HPA", "POD", "DAEMONSET",
      "DEPLOYMENT", "STATEFULSET", "CADVISOR", "KUBELET", "DCGM", "JOBSET",
    ]
    managed_prometheus {
      enabled = true
    }
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  dns_config {
    # The API reports this cluster's clusterDns as "KUBE_DNS" (in-cluster
    # kube-dns, not Cloud DNS) — the provider's own enum for that same
    # state is "PLATFORM_DEFAULT".
    cluster_dns = "PLATFORM_DEFAULT"
  }

  # Node pools are managed as standalone resources below. This cluster
  # already exists with its default pool long since removed, so the live
  # value is 0, not 1 — initial_node_count only matters at first creation
  # (sizing the transient default pool before remove_default_node_pool
  # deletes it) and is a ForceNew field: setting it to anything but the
  # imported value here would try to destroy and recreate prod-gke.
  remove_default_node_pool = true
  initial_node_count       = 0

  node_locations = [
    "me-central1-a", "me-central1-b", "me-central1-c",
  ]

  deletion_protection = true
}

# ---------------------------------------------------------------------
# Management node pool: exactly one node, publicly reachable, tainted so
# only workloads that explicitly tolerate `workload=management` land here
# (ArgoCD, Vault, ESO, Prometheus).
# ---------------------------------------------------------------------
resource "google_container_node_pool" "management" {
  project        = var.project_id
  name           = var.management_pool.name
  location       = var.region
  cluster        = google_container_cluster.this.name
  node_count     = var.management_pool.node_count
  node_locations = [var.management_pool.zones[0]]

  node_config {
    machine_type = var.management_pool.machine_type
    disk_type    = var.management_pool.disk_type
    disk_size_gb = var.management_pool.disk_size_gb
    image_type   = "COS_CONTAINERD"

    labels = {
      (var.management_pool.label_key) = var.management_pool.label_value
    }

    taint {
      key    = var.management_pool.taint_key
      value  = var.management_pool.taint_value
      effect = "NO_SCHEDULE"
    }

    shielded_instance_config {
      enable_integrity_monitoring = true
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/service.management.readonly",
      "https://www.googleapis.com/auth/servicecontrol",
      "https://www.googleapis.com/auth/trace.append",
    ]
  }

  # This is the ONE node pool that intentionally has external node IPs
  # (management-pool nodes are not private) — do not flip this to true.
  network_config {
    enable_private_nodes = false
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_unavailable = 1
    strategy        = "SURGE"
    max_surge       = 0
  }
}

# ---------------------------------------------------------------------
# Application node pool: private nodes only, one per zone, no taint —
# runs backend/frontend/postgres.
# ---------------------------------------------------------------------
resource "google_container_node_pool" "application" {
  project        = var.project_id
  name           = var.application_pool.name
  location       = var.region
  cluster        = google_container_cluster.this.name
  node_count     = var.application_pool.node_count
  node_locations = var.application_pool.zones

  node_config {
    machine_type = var.application_pool.machine_type
    disk_type    = var.application_pool.disk_type
    disk_size_gb = var.application_pool.disk_size_gb
    image_type   = "COS_CONTAINERD"

    labels = {
      (var.application_pool.label_key) = var.application_pool.label_value
    }

    shielded_instance_config {
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/service.management.readonly",
      "https://www.googleapis.com/auth/servicecontrol",
      "https://www.googleapis.com/auth/trace.append",
    ]
  }

  # These nodes have NO external IPs — do not flip this to false.
  network_config {
    enable_private_nodes = true
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_unavailable = 1
    strategy        = "SURGE"
    max_surge       = 0
  }
}
