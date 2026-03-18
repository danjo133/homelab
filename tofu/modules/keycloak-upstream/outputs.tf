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

output "user_passwords" {
  description = "Generated initial passwords for upstream realm users"
  value = merge(
    { for u in local.example_users : u => random_password.user[u].result },
    { for u in var.extra_users : u.username => random_password.extra[u.username].result },
  )
  sensitive = true
}
