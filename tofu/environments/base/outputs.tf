output "broker_client_secret" {
  description = "Secret of the upstream broker-client (for seeding into cluster Vault namespaces)"
  value       = module.keycloak_upstream.broker_client_secret
  sensitive   = true
}
