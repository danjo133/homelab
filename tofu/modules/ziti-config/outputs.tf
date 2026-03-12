output "cluster_router_ids" {
  description = "Edge router IDs per cluster"
  value       = { for k, v in ziti_edge_router.cluster : k => v.id }
}

output "service_ids" {
  description = "Service IDs for support services"
  value       = { for k, v in ziti_service.support : k => v.id }
}

output "admin_client_id" {
  description = "Admin client identity ID"
  value       = ziti_identity.admin_client.id
}

output "admin_client_enrollment_token" {
  description = "Admin client enrollment JWT (one-time use)"
  value       = ziti_identity.admin_client.enrollment_token
  sensitive   = true
}
