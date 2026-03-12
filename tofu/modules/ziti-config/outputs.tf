output "cluster_router_ids" {
  description = "Edge router IDs per cluster"
  value       = { for k, v in ziti_edge_router.cluster : k => v.id }
}

output "service_ids" {
  description = "Service IDs for overlay services"
  value       = { for k, v in ziti_service.overlay : k => v.id }
}

output "client_device_ids" {
  description = "Client device identity IDs"
  value       = { for k, v in ziti_identity.client : k => v.id }
}

output "client_device_enrollment_tokens" {
  description = "Client device enrollment JWTs (one-time use)"
  value       = { for k, v in ziti_identity.client : k => v.enrollment_token }
  sensitive   = true
}
