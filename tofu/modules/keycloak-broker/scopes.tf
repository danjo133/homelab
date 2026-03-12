# Client scopes and protocol mappers for the broker realm.
#
# Keycloak auto-creates built-in scopes (profile, email, roles, acr,
# web-origins, etc.) when a realm is created. We only create custom
# scopes (openid, groups) and leave the built-in ones untouched.

# ============================================================================
# Custom Client Scopes
# ============================================================================

resource "keycloak_openid_client_scope" "openid" {
  realm_id               = keycloak_realm.broker.id
  name                   = "openid"
  description            = "OpenID Connect scope"
  include_in_token_scope = true
}

resource "keycloak_openid_client_scope" "groups" {
  realm_id               = keycloak_realm.broker.id
  name                   = "groups"
  description            = "Group membership"
  include_in_token_scope = true
  consent_screen_text    = "Group membership"
}

# ============================================================================
# Protocol Mappers — openid scope
# ============================================================================

resource "keycloak_generic_protocol_mapper" "openid_sub" {
  realm_id        = keycloak_realm.broker.id
  client_scope_id = keycloak_openid_client_scope.openid.id
  name            = "sub"
  protocol        = "openid-connect"
  protocol_mapper = "oidc-sub-mapper"
  config = {
    "introspection.token.claim" = "true"
    "access.token.claim"        = "true"
  }
}

# ============================================================================
# Protocol Mappers — groups scope
# ============================================================================

resource "keycloak_openid_group_membership_protocol_mapper" "group_membership" {
  realm_id        = keycloak_realm.broker.id
  client_scope_id = keycloak_openid_client_scope.groups.id
  name            = "group-membership"

  claim_name          = "groups"
  full_path           = false
  add_to_id_token     = true
  add_to_access_token = true
  add_to_userinfo     = true
}

# ============================================================================
# Default Client Scopes for the Realm
# ============================================================================

resource "keycloak_realm_default_client_scopes" "broker" {
  realm_id = keycloak_realm.broker.id

  default_scopes = [
    "acr",
    "profile",
    "email",
    "roles",
    keycloak_openid_client_scope.openid.name,
    keycloak_openid_client_scope.groups.name,
  ]
}
