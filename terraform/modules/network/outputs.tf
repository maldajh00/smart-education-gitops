output "network_id" {
  description = "Self link / ID of the VPC network."
  value       = google_compute_network.this.id
}

output "network_name" {
  value = google_compute_network.this.name
}

output "subnet_id" {
  description = "Self link / ID of the GKE subnet."
  value       = google_compute_subnetwork.gke.id
}

output "subnet_name" {
  value = google_compute_subnetwork.gke.name
}

output "subnet_self_link" {
  value = google_compute_subnetwork.gke.self_link
}

output "router_name" {
  value = google_compute_router.nat.name
}
