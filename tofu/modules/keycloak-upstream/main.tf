# Keycloak upstream realm — the "corporate IdP" on the support VM.
#
# Manages:
#   - upstream realm
#   - admin + user realm roles
#   - 3 example users (alice, bob, carol) + configurable extra users
#   - 3 OIDC clients: broker-client, teleport, gitlab
#   - realm-roles protocol mapper on the teleport client

# ============================================================================
# Realm
# ============================================================================

resource "keycloak_realm" "upstream" {
  realm        = "upstream"
  enabled      = true
  display_name = "Upstream Corporate IdP"

  registration_allowed     = false
  login_with_email_allowed = true
  duplicate_emails_allowed = false
  reset_password_allowed   = true
  edit_username_allowed    = false

  security_defenses {
    brute_force_detection {
      permanent_lockout = false
    }
  }

  access_token_lifespan    = "5m"  # 300s
  sso_session_idle_timeout = "30m" # 1800s
  sso_session_max_lifespan = "10h" # 36000s
}

# ============================================================================
# Realm Roles
# ============================================================================

resource "keycloak_role" "admin" {
  realm_id    = keycloak_realm.upstream.id
  name        = "admin"
  description = "admin role"
}

resource "keycloak_role" "user" {
  realm_id    = keycloak_realm.upstream.id
  name        = "user"
  description = "user role"
}

# ============================================================================
# Users
# ============================================================================

locals {
  example_users = ["alice", "bob", "carol"]
}

resource "random_password" "user" {
  for_each = toset(local.example_users)
  length   = 20
  special  = false
}

resource "keycloak_user" "alice" {
  realm_id       = keycloak_realm.upstream.id
  username       = "alice"
  email          = "alice@example.com"
  first_name     = "Alice"
  last_name      = "Admin"
  enabled        = true
  email_verified = true

  initial_password {
    value     = random_password.user["alice"].result
    temporary = false
  }

  lifecycle { ignore_changes = [initial_password] }
}

resource "keycloak_user_roles" "alice" {
  realm_id   = keycloak_realm.upstream.id
  user_id    = keycloak_user.alice.id
  role_ids   = [keycloak_role.admin.id]
  exhaustive = false
}

resource "keycloak_user" "bob" {
  realm_id       = keycloak_realm.upstream.id
  username       = "bob"
  email          = "bob@example.com"
  first_name     = "Bob"
  last_name      = "Builder"
  enabled        = true
  email_verified = true

  initial_password {
    value     = random_password.user["bob"].result
    temporary = false
  }

  lifecycle { ignore_changes = [initial_password] }
}

resource "keycloak_user_roles" "bob" {
  realm_id   = keycloak_realm.upstream.id
  user_id    = keycloak_user.bob.id
  role_ids   = [keycloak_role.user.id]
  exhaustive = false
}

resource "keycloak_user" "carol" {
  realm_id       = keycloak_realm.upstream.id
  username       = "carol"
  email          = "carol@example.com"
  first_name     = "Carol"
  last_name      = "Checker"
  enabled        = true
  email_verified = true

  initial_password {
    value     = random_password.user["carol"].result
    temporary = false
  }

  lifecycle { ignore_changes = [initial_password] }
}

resource "keycloak_user_roles" "carol" {
  realm_id   = keycloak_realm.upstream.id
  user_id    = keycloak_user.carol.id
  role_ids   = [keycloak_role.user.id]
  exhaustive = false
}

# ============================================================================
# Extra users (from config.yaml)
# ============================================================================

resource "random_password" "extra" {
  for_each = { for u in var.extra_users : u.username => u }
  length   = 20
  special  = false
}

resource "keycloak_user" "extra" {
  for_each       = { for u in var.extra_users : u.username => u }
  realm_id       = keycloak_realm.upstream.id
  username       = each.value.username
  email          = each.value.email
  first_name     = each.value.first_name
  last_name      = each.value.last_name
  enabled        = true
  email_verified = true

  initial_password {
    value     = random_password.extra[each.key].result
    temporary = false
  }

  lifecycle { ignore_changes = [initial_password] }
}

resource "keycloak_user_roles" "extra" {
  for_each   = { for u in var.extra_users : u.username => u }
  realm_id   = keycloak_realm.upstream.id
  user_id    = keycloak_user.extra[each.key].id
  role_ids   = [each.value.role == "admin" ? keycloak_role.admin.id : keycloak_role.user.id]
  exhaustive = false
}

# ============================================================================
# OIDC Clients
# ============================================================================

# broker-client — used by per-cluster broker Keycloak to federate
resource "keycloak_openid_client" "broker_client" {
  realm_id  = keycloak_realm.upstream.id
  client_id = "broker-client"
  name      = "Broker IdP Federation Client"
  enabled   = true

  access_type                  = "CONFIDENTIAL"
  standard_flow_enabled        = true
  direct_access_grants_enabled = false
  service_accounts_enabled     = false
  use_refresh_tokens           = false

  valid_redirect_uris = var.broker_redirect_uris
  web_origins = ["+"]

  lifecycle { ignore_changes = [client_secret] }
}

# teleport — used by Teleport access plane for OIDC auth
resource "keycloak_openid_client" "teleport" {
  realm_id  = keycloak_realm.upstream.id
  client_id = "teleport"
  name      = "Teleport Access Plane"
  enabled   = true

  access_type                  = "CONFIDENTIAL"
  standard_flow_enabled        = true
  direct_access_grants_enabled = false
  service_accounts_enabled     = false
  use_refresh_tokens           = false

  valid_redirect_uris = [
    "https://teleport.${var.support_domain}:3080/v1/webapi/oidc/callback",
  ]
  web_origins = ["+"]

  lifecycle { ignore_changes = [client_secret] }
}

# realm-roles protocol mapper on broker-client — ensures realm_access.roles
# is in the ID token so broker IdP mappers can assign groups based on roles
resource "keycloak_openid_user_realm_role_protocol_mapper" "broker_realm_roles" {
  realm_id  = keycloak_realm.upstream.id
  client_id = keycloak_openid_client.broker_client.id
  name      = "realm-roles"

  claim_name          = "realm_access.roles"
  multivalued         = true
  add_to_id_token     = true
  add_to_access_token = true
  add_to_userinfo     = true
}

# realm-roles protocol mapper on teleport client
resource "keycloak_openid_user_realm_role_protocol_mapper" "teleport_realm_roles" {
  realm_id  = keycloak_realm.upstream.id
  client_id = keycloak_openid_client.teleport.id
  name      = "realm-roles"

  claim_name          = "realm_access.roles"
  multivalued         = true
  add_to_id_token     = true
  add_to_access_token = true
  add_to_userinfo     = true
}

# gitlab — used by GitLab CE for OIDC auth
resource "keycloak_openid_client" "gitlab" {
  realm_id  = keycloak_realm.upstream.id
  client_id = "gitlab"
  name      = "GitLab CE"
  enabled   = true

  access_type                  = "CONFIDENTIAL"
  standard_flow_enabled        = true
  direct_access_grants_enabled = false
  service_accounts_enabled     = false
  use_refresh_tokens           = false

  valid_redirect_uris = [
    "https://gitlab.${var.support_domain}/users/auth/openid_connect/callback",
  ]
  web_origins = ["+"]

  lifecycle { ignore_changes = [client_secret] }
}
