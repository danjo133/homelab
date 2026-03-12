output "cluster_token_names" {
  description = "Provision token names per cluster"
  value       = { for k, v in teleport_provision_token.cluster : k => v.metadata.name }
  sensitive   = true
}
