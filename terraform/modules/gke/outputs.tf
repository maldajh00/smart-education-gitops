output "cluster_name" {
  value = google_container_cluster.this.name
}

output "cluster_id" {
  value = google_container_cluster.this.id
}

output "endpoint" {
  description = "GKE control-plane public endpoint."
  value       = google_container_cluster.this.endpoint
  sensitive   = true
}

output "ca_certificate" {
  value     = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive = true
}

output "workload_identity_pool" {
  value = google_container_cluster.this.workload_identity_config[0].workload_pool
}
