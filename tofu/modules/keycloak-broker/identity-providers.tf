# Identity providers for the broker realm.
#
# Upstream (corporate) IdP + 3 social providers (Google, GitHub, Microsoft).
# Each provider has mappers to assign federated users to broker groups.

# ============================================================================
# Upstream Corporate IdP (OIDC)
# ============================================================================

resource "keycloak_oidc_identity_provider" "upstream" {
  realm        = keycloak_realm.broker.id
  alias        = "upstream"
  display_name = "Corporate Login"
  enabled      = true
  trust_email  = true

  first_broker_login_flow_alias = "first broker login"

  authorization_url = "${var.upstream_issuer}/protocol/openid-connect/auth"
  token_url         = "${var.upstream_issuer}/protocol/openid-connect/token"
  user_info_url     = "${var.upstream_issuer}/protocol/openid-connect/userinfo"
  jwks_url          = "${var.upstream_issuer}/protocol/openid-connect/certs"
  logout_url        = "${var.upstream_issuer}/protocol/openid-connect/logout"
  issuer            = var.upstream_issuer

  client_id     = var.upstream_client_id
  client_secret = var.upstream_client_secret

  sync_mode          = "IMPORT"
  default_scopes     = "openid profile email roles"
  validate_signature = true

  extra_config = {
    "clientAuthMethod" = "client_secret_post"
  }
}

# ============================================================================
# Google Social IdP
# ============================================================================

resource "keycloak_oidc_identity_provider" "google" {
  realm        = keycloak_realm.broker.id
  alias        = "google"
  provider_id  = "google"
  display_name = "Google"
  enabled      = true
  trust_email  = true

  first_broker_login_flow_alias = "first broker login"

  # Google's well-known endpoints are used automatically by the google provider
  authorization_url = ""
  token_url         = ""

  client_id     = var.google_client_id
  client_secret = var.google_client_secret

  sync_mode      = "IMPORT"
  default_scopes = "openid profile email"
}

# ============================================================================
# GitHub Social IdP
# ============================================================================

resource "keycloak_oidc_identity_provider" "github" {
  realm        = keycloak_realm.broker.id
  alias        = "github"
  provider_id  = "github"
  display_name = "GitHub"
  enabled      = true
  trust_email  = true

  first_broker_login_flow_alias = "first broker login"

  authorization_url = ""
  token_url         = ""

  client_id     = var.github_client_id
  client_secret = var.github_client_secret

  sync_mode = "IMPORT"
}

# ============================================================================
# Microsoft Social IdP
# ============================================================================

resource "keycloak_oidc_identity_provider" "microsoft" {
  realm        = keycloak_realm.broker.id
  alias        = "microsoft"
  provider_id  = "microsoft"
  display_name = "Microsoft"
  enabled      = true
  trust_email  = true

  first_broker_login_flow_alias = "first broker login"

  authorization_url = ""
  token_url         = ""

  client_id     = var.microsoft_client_id
  client_secret = var.microsoft_client_secret

  sync_mode      = "IMPORT"
  default_scopes = "openid profile email"
}

# ============================================================================
# Upstream IdP Mappers — map upstream roles to broker groups
# ============================================================================

# Admin role → all 6 groups
resource "keycloak_custom_identity_provider_mapper" "upstream_admin_to_platform_admins" {
  realm                    = keycloak_realm.broker.id
  name                     = "upstream-admin-to-platform-admins"
  identity_provider_alias  = keycloak_oidc_identity_provider.upstream.alias
  identity_provider_mapper = "oidc-advanced-group-idp-mapper"

  extra_config = {
    syncMode                = "INHERIT"
    claims                  = "[{\"key\":\"realm_access.roles\",\"value\":\"admin\"}]"
    "are.claim.values.regex" = "false"
    group                   = "/${keycloak_group.platform_admins.name}"
  }
}

resource "keycloak_custom_identity_provider_mapper" "upstream_admin_to_k8s_admins" {
  realm                    = keycloak_realm.broker.id
  name                     = "upstream-admin-to-k8s-admins"
  identity_provider_alias  = keycloak_oidc_identity_provider.upstream.alias
  identity_provider_mapper = "oidc-advanced-group-idp-mapper"

  extra_config = {
    syncMode                = "INHERIT"
    claims                  = "[{\"key\":\"realm_access.roles\",\"value\":\"admin\"}]"
    "are.claim.values.regex" = "false"
    group                   = "/${keycloak_group.k8s_admins.name}"
  }
}

resource "keycloak_custom_identity_provider_mapper" "upstream_admin_to_k8s_operators" {
  realm                    = keycloak_realm.broker.id
  name                     = "upstream-admin-to-k8s-operators"
  identity_provider_alias  = keycloak_oidc_identity_provider.upstream.alias
  identity_provider_mapper = "oidc-advanced-group-idp-mapper"

  extra_config = {
    syncMode                = "INHERIT"
    claims                  = "[{\"key\":\"realm_access.roles\",\"value\":\"admin\"}]"
    "are.claim.values.regex" = "false"
    group                   = "/${keycloak_group.k8s_operators.name}"
  }
}

resource "keycloak_custom_identity_provider_mapper" "upstream_admin_to_web_admins" {
  realm                    = keycloak_realm.broker.id
  name                     = "upstream-admin-to-web-admins"
  identity_provider_alias  = keycloak_oidc_identity_provider.upstream.alias
  identity_provider_mapper = "oidc-advanced-group-idp-mapper"

  extra_config = {
    syncMode                = "INHERIT"
    claims                  = "[{\"key\":\"realm_access.roles\",\"value\":\"admin\"}]"
    "are.claim.values.regex" = "false"
    group                   = "/${keycloak_group.web_admins.name}"
  }
}

resource "keycloak_custom_identity_provider_mapper" "upstream_admin_to_web_operators" {
  realm                    = keycloak_realm.broker.id
  name                     = "upstream-admin-to-web-operators"
  identity_provider_alias  = keycloak_oidc_identity_provider.upstream.alias
  identity_provider_mapper = "oidc-advanced-group-idp-mapper"

  extra_config = {
    syncMode                = "INHERIT"
    claims                  = "[{\"key\":\"realm_access.roles\",\"value\":\"admin\"}]"
    "are.claim.values.regex" = "false"
    group                   = "/${keycloak_group.web_operators.name}"
  }
}

resource "keycloak_custom_identity_provider_mapper" "upstream_admin_to_app_users" {
  realm                    = keycloak_realm.broker.id
  name                     = "upstream-admin-to-app-users"
  identity_provider_alias  = keycloak_oidc_identity_provider.upstream.alias
  identity_provider_mapper = "oidc-advanced-group-idp-mapper"

  extra_config = {
    syncMode                = "INHERIT"
    claims                  = "[{\"key\":\"realm_access.roles\",\"value\":\"admin\"}]"
    "are.claim.values.regex" = "false"
    group                   = "/${keycloak_group.app_users.name}"
  }
}

# User role → app-users only
resource "keycloak_custom_identity_provider_mapper" "upstream_user_to_app_users" {
  realm                    = keycloak_realm.broker.id
  name                     = "upstream-user-to-app-users"
  identity_provider_alias  = keycloak_oidc_identity_provider.upstream.alias
  identity_provider_mapper = "oidc-advanced-group-idp-mapper"

  extra_config = {
    syncMode                = "INHERIT"
    claims                  = "[{\"key\":\"realm_access.roles\",\"value\":\"user\"}]"
    "are.claim.values.regex" = "false"
    group                   = "/${keycloak_group.app_users.name}"
  }
}

# ============================================================================
# Social IdP Mappers — all social users → app-users group
# ============================================================================

resource "keycloak_custom_identity_provider_mapper" "google_to_app_users" {
  realm                    = keycloak_realm.broker.id
  name                     = "google-to-app-users"
  identity_provider_alias  = keycloak_oidc_identity_provider.google.alias
  identity_provider_mapper = "oidc-hardcoded-group-idp-mapper"

  extra_config = {
    syncMode = "INHERIT"
    group    = "/${keycloak_group.app_users.name}"
  }
}

resource "keycloak_custom_identity_provider_mapper" "github_to_app_users" {
  realm                    = keycloak_realm.broker.id
  name                     = "github-to-app-users"
  identity_provider_alias  = keycloak_oidc_identity_provider.github.alias
  identity_provider_mapper = "oidc-hardcoded-group-idp-mapper"

  extra_config = {
    syncMode = "INHERIT"
    group    = "/${keycloak_group.app_users.name}"
  }
}

resource "keycloak_custom_identity_provider_mapper" "microsoft_to_app_users" {
  realm                    = keycloak_realm.broker.id
  name                     = "microsoft-to-app-users"
  identity_provider_alias  = keycloak_oidc_identity_provider.microsoft.alias
  identity_provider_mapper = "oidc-hardcoded-group-idp-mapper"

  extra_config = {
    syncMode = "INHERIT"
    group    = "/${keycloak_group.app_users.name}"
  }
}
