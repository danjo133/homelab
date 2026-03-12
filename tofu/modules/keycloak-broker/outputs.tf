output "realm_id" {
  description = "ID of the broker realm"
  value       = keycloak_realm.broker.id
}

output "oauth2_proxy_client_secret" {
  description = "Secret of the oauth2-proxy client"
  value       = keycloak_openid_client.oauth2_proxy.client_secret
  sensitive   = true
}

output "argocd_client_secret" {
  description = "Secret of the argocd client"
  value       = keycloak_openid_client.argocd.client_secret
  sensitive   = true
}

output "grafana_client_secret" {
  description = "Secret of the grafana client"
  value       = keycloak_openid_client.grafana.client_secret
  sensitive   = true
}

output "jit_service_client_secret" {
  description = "Secret of the jit-service client"
  value       = keycloak_openid_client.jit_service.client_secret
  sensitive   = true
}

output "kiali_client_secret" {
  description = "Secret of the kiali client"
  value       = keycloak_openid_client.kiali.client_secret
  sensitive   = true
}

output "headlamp_client_secret" {
  description = "Secret of the headlamp client"
  value       = keycloak_openid_client.headlamp.client_secret
  sensitive   = true
}
