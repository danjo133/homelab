output "realm_id" {
  description = "ID of the upstream realm"
  value       = keycloak_realm.upstream.id
}

output "broker_client_id" {
  description = "UUID of the broker-client"
  value       = keycloak_openid_client.broker_client.id
}

output "broker_client_secret" {
  description = "Secret of the broker-client"
  value       = keycloak_openid_client.broker_client.client_secret
  sensitive   = true
}

output "teleport_client_secret" {
  description = "Secret of the teleport client"
  value       = keycloak_openid_client.teleport.client_secret
  sensitive   = true
}

output "gitlab_client_secret" {
  description = "Secret of the gitlab client"
  value       = keycloak_openid_client.gitlab.client_secret
  sensitive   = true
}
