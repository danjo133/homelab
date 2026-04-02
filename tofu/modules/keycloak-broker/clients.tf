# OIDC clients for the broker realm.
#
# 8 clients: kubernetes (public), oauth2-proxy, argocd, grafana,
# jit-service, kiali, headlamp, open-webui (all confidential except kubernetes).
#
# Redirect URIs are derived from var.domain for per-cluster configuration.

# ============================================================================
# kubernetes — public client for kubectl OIDC auth
# ============================================================================

resource "keycloak_openid_client" "kubernetes" {
  realm_id  = keycloak_realm.broker.id
  client_id = "kubernetes"
  name      = "Kubernetes kubectl"
  enabled   = true

  access_type                  = "PUBLIC"
  standard_flow_enabled        = true
  direct_access_grants_enabled = true

  valid_redirect_uris = [
    "http://localhost:8000",
    "http://localhost:18000",
    "http://127.0.0.1:8000",
    "http://127.0.0.1:18000",
    "https://jit.${var.domain}/*",
  ]
  web_origins = [
    "http://localhost:8000",
    "http://localhost:18000",
    "https://jit.${var.domain}",
  ]

  extra_config = {
    "oidc.token.exchange.standard.enabled" = "true"
  }
}

# Audience mapper — include jit-service in kubernetes client access tokens
resource "keycloak_openid_audience_protocol_mapper" "kubernetes_jit_audience" {
  realm_id  = keycloak_realm.broker.id
  client_id = keycloak_openid_client.kubernetes.id
  name      = "jit-service-audience"

  included_client_audience = keycloak_openid_client.jit_service.client_id

  add_to_id_token     = false
  add_to_access_token = true
}

# Client default scopes for kubernetes
resource "keycloak_openid_client_default_scopes" "kubernetes" {
  realm_id  = keycloak_realm.broker.id
  client_id = keycloak_openid_client.kubernetes.id

  default_scopes = [
    "acr",
    "profile",
    "email",
    "roles",
    keycloak_openid_client_scope.openid.name,
    keycloak_openid_client_scope.groups.name,
  ]
}

# ============================================================================
# oauth2-proxy — confidential client for web SSO
# ============================================================================

resource "keycloak_openid_client" "oauth2_proxy" {
  realm_id  = keycloak_realm.broker.id
  client_id = "oauth2-proxy"
  name      = "OAuth2 Proxy (Web SSO)"
  enabled   = true

  access_type                  = "CONFIDENTIAL"
  standard_flow_enabled        = true
  direct_access_grants_enabled = false
  service_accounts_enabled     = false

  valid_redirect_uris = [
    "https://oauth2-proxy.${var.domain}/oauth2/callback",
  ]
  web_origins = ["+"]

  lifecycle { ignore_changes = [client_secret] }
}

resource "keycloak_openid_client_default_scopes" "oauth2_proxy" {
  realm_id  = keycloak_realm.broker.id
  client_id = keycloak_openid_client.oauth2_proxy.id

  default_scopes = [
    "acr",
    "profile",
    "email",
    "roles",
    keycloak_openid_client_scope.openid.name,
    keycloak_openid_client_scope.groups.name,
  ]
}

# ============================================================================
# argocd — confidential client for ArgoCD OIDC
# ============================================================================

resource "keycloak_openid_client" "argocd" {
  realm_id  = keycloak_realm.broker.id
  client_id = "argocd"
  name      = "ArgoCD"
  enabled   = true

  access_type                  = "CONFIDENTIAL"
  standard_flow_enabled        = true
  direct_access_grants_enabled = false
  service_accounts_enabled     = false

  valid_redirect_uris = [
    "https://argocd.${var.domain}/auth/callback",
  ]
  web_origins = [
    "https://argocd.${var.domain}",
  ]

  lifecycle { ignore_changes = [client_secret] }
}

resource "keycloak_openid_client_default_scopes" "argocd" {
  realm_id  = keycloak_realm.broker.id
  client_id = keycloak_openid_client.argocd.id

  default_scopes = [
    "acr",
    "profile",
    "email",
    "roles",
    keycloak_openid_client_scope.openid.name,
    keycloak_openid_client_scope.groups.name,
  ]
}

# ============================================================================
# grafana — confidential client for Grafana OIDC
# ============================================================================

resource "keycloak_openid_client" "grafana" {
  realm_id  = keycloak_realm.broker.id
  client_id = "grafana"
  name      = "Grafana"
  enabled   = true

  access_type                  = "CONFIDENTIAL"
  standard_flow_enabled        = true
  direct_access_grants_enabled = false
  service_accounts_enabled     = false

  valid_redirect_uris = [
    "https://grafana.${var.domain}/login/generic_oauth",
  ]
  web_origins = [
    "https://grafana.${var.domain}",
  ]

  lifecycle { ignore_changes = [client_secret] }
}

resource "keycloak_openid_client_default_scopes" "grafana" {
  realm_id  = keycloak_realm.broker.id
  client_id = keycloak_openid_client.grafana.id

  default_scopes = [
    "acr",
    "profile",
    "email",
    "roles",
    keycloak_openid_client_scope.openid.name,
    keycloak_openid_client_scope.groups.name,
  ]
}

# ============================================================================
# jit-service — confidential client with token-exchange for JIT elevation
# ============================================================================

resource "keycloak_openid_client" "jit_service" {
  realm_id  = keycloak_realm.broker.id
  client_id = "jit-service"
  name      = "JIT Role Elevation Service"
  enabled   = true

  access_type                  = "CONFIDENTIAL"
  standard_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = true

  extra_config = {
    "oidc.token.exchange.standard.enabled" = "true"
  }

  lifecycle { ignore_changes = [client_secret] }
}

resource "keycloak_openid_client_default_scopes" "jit_service" {
  realm_id  = keycloak_realm.broker.id
  client_id = keycloak_openid_client.jit_service.id

  default_scopes = [
    "acr",
    "profile",
    "email",
    "roles",
    keycloak_openid_client_scope.openid.name,
    keycloak_openid_client_scope.groups.name,
  ]
}

# ============================================================================
# kiali — confidential client for Istio mesh UI OIDC
# ============================================================================

resource "keycloak_openid_client" "kiali" {
  realm_id  = keycloak_realm.broker.id
  client_id = "kiali"
  name      = "Kiali (Istio Mesh UI)"
  enabled   = true

  access_type                  = "CONFIDENTIAL"
  standard_flow_enabled        = true
  direct_access_grants_enabled = false
  service_accounts_enabled     = false

  valid_redirect_uris = [
    "https://kiali.${var.domain}/*",
  ]
  web_origins = [
    "https://kiali.${var.domain}",
  ]

  lifecycle { ignore_changes = [client_secret] }
}

resource "keycloak_openid_client_default_scopes" "kiali" {
  realm_id  = keycloak_realm.broker.id
  client_id = keycloak_openid_client.kiali.id

  default_scopes = [
    "acr",
    "profile",
    "email",
    "roles",
    keycloak_openid_client_scope.openid.name,
    keycloak_openid_client_scope.groups.name,
  ]
}

# ============================================================================
# headlamp — confidential client for K8s dashboard OIDC
# ============================================================================

resource "keycloak_openid_client" "headlamp" {
  realm_id  = keycloak_realm.broker.id
  client_id = "headlamp"
  name      = "Headlamp (K8s Dashboard)"
  enabled   = true

  access_type                  = "CONFIDENTIAL"
  standard_flow_enabled        = true
  direct_access_grants_enabled = false
  service_accounts_enabled     = false

  valid_redirect_uris = [
    "https://headlamp.${var.domain}/*",
  ]
  web_origins = [
    "https://headlamp.${var.domain}",
  ]

  lifecycle { ignore_changes = [client_secret] }
}

# Audience mapper — include kubernetes in headlamp id_token so K8s API
# server accepts it (oidc-client-id=kubernetes on API server)
resource "keycloak_openid_audience_protocol_mapper" "headlamp_kubernetes_audience" {
  realm_id  = keycloak_realm.broker.id
  client_id = keycloak_openid_client.headlamp.id
  name      = "kubernetes-audience"

  included_client_audience = keycloak_openid_client.kubernetes.client_id

  add_to_id_token     = true
  add_to_access_token = true
}

resource "keycloak_openid_client_default_scopes" "headlamp" {
  realm_id  = keycloak_realm.broker.id
  client_id = keycloak_openid_client.headlamp.id

  default_scopes = [
    "acr",
    "profile",
    "email",
    "roles",
    keycloak_openid_client_scope.openid.name,
    keycloak_openid_client_scope.groups.name,
  ]
}

# ============================================================================
# open-webui — confidential client for Open WebUI OIDC
# ============================================================================

resource "keycloak_openid_client" "open_webui" {
  realm_id  = keycloak_realm.broker.id
  client_id = "open-webui"
  name      = "Open WebUI"
  enabled   = true

  access_type                  = "CONFIDENTIAL"
  standard_flow_enabled        = true
  direct_access_grants_enabled = false
  service_accounts_enabled     = false

  valid_redirect_uris = [
    "https://chat.${var.domain}/oauth/oidc/callback",
  ]
  web_origins = [
    "https://chat.${var.domain}",
  ]

  lifecycle { ignore_changes = [client_secret] }
}

resource "keycloak_openid_client_default_scopes" "open_webui" {
  realm_id  = keycloak_realm.broker.id
  client_id = keycloak_openid_client.open_webui.id

  default_scopes = [
    "acr",
    "profile",
    "email",
    "roles",
    keycloak_openid_client_scope.openid.name,
    keycloak_openid_client_scope.groups.name,
  ]
}

# ============================================================================
# dependency-track — confidential client for Dependency-Track OIDC
# ============================================================================

resource "keycloak_openid_client" "dependency_track" {
  realm_id  = keycloak_realm.broker.id
  client_id = "dependency-track"
  name      = "Dependency-Track"
  enabled   = true

  access_type                  = "PUBLIC"
  standard_flow_enabled        = true
  direct_access_grants_enabled = false
  service_accounts_enabled     = false
  pkce_code_challenge_method   = "S256"

  valid_redirect_uris = [
    "https://dtrack.${var.domain}/*",
  ]
  web_origins = [
    "https://dtrack.${var.domain}",
  ]
}

resource "keycloak_openid_client_default_scopes" "dependency_track" {
  realm_id  = keycloak_realm.broker.id
  client_id = keycloak_openid_client.dependency_track.id

  default_scopes = [
    "acr",
    "profile",
    "email",
    "roles",
    keycloak_openid_client_scope.openid.name,
    keycloak_openid_client_scope.groups.name,
  ]
}
