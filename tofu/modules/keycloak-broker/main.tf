# Keycloak broker realm — per-cluster broker IdP that federates from upstream.
#
# Manages:
#   - broker realm
#   - 6 realm roles + 6 groups with role mappings
#   - Client scopes, identity providers, IdP mappers
#   - 7 OIDC clients (kubernetes, oauth2-proxy, argocd, grafana, jit-service, kiali, headlamp)

# ============================================================================
# Realm
# ============================================================================

resource "keycloak_realm" "broker" {
  realm        = "broker"
  enabled      = true
  display_name = "Broker IdP"

  registration_allowed     = false
  login_with_email_allowed = true
  duplicate_emails_allowed = false
  reset_password_allowed   = false
  edit_username_allowed    = false
}

# ============================================================================
# Realm Roles
# ============================================================================

resource "keycloak_role" "platform_admin" {
  realm_id    = keycloak_realm.broker.id
  name        = "platform-admin"
  description = "Full admin of everything (k8s + web + apps)"
}

resource "keycloak_role" "k8s_admin" {
  realm_id    = keycloak_realm.broker.id
  name        = "k8s-admin"
  description = "Full Kubernetes cluster-admin"
}

resource "keycloak_role" "k8s_operator" {
  realm_id    = keycloak_realm.broker.id
  name        = "k8s-operator"
  description = "Read-only Kubernetes operator (pods, logs, deploys)"
}

resource "keycloak_role" "web_admin" {
  realm_id    = keycloak_realm.broker.id
  name        = "web-admin"
  description = "Admin of web UIs (Grafana, Hubble, ArgoCD)"
}

resource "keycloak_role" "web_operator" {
  realm_id    = keycloak_realm.broker.id
  name        = "web-operator"
  description = "Read/use web UIs"
}

resource "keycloak_role" "app_user" {
  realm_id    = keycloak_realm.broker.id
  name        = "app-user"
  description = "Regular user of deployed apps"
}

# ============================================================================
# Groups
# ============================================================================

resource "keycloak_group" "platform_admins" {
  realm_id = keycloak_realm.broker.id
  name     = "platform-admins"
}

resource "keycloak_group" "k8s_admins" {
  realm_id = keycloak_realm.broker.id
  name     = "k8s-admins"
}

resource "keycloak_group" "k8s_operators" {
  realm_id = keycloak_realm.broker.id
  name     = "k8s-operators"
}

resource "keycloak_group" "web_admins" {
  realm_id = keycloak_realm.broker.id
  name     = "web-admins"
}

resource "keycloak_group" "web_operators" {
  realm_id = keycloak_realm.broker.id
  name     = "web-operators"
}

resource "keycloak_group" "app_users" {
  realm_id = keycloak_realm.broker.id
  name     = "app-users"
}

# ============================================================================
# Group → Role Mappings
# ============================================================================

resource "keycloak_group_roles" "platform_admins" {
  realm_id = keycloak_realm.broker.id
  group_id = keycloak_group.platform_admins.id
  role_ids = [keycloak_role.platform_admin.id]
}

resource "keycloak_group_roles" "k8s_admins" {
  realm_id = keycloak_realm.broker.id
  group_id = keycloak_group.k8s_admins.id
  role_ids = [keycloak_role.k8s_admin.id]
}

resource "keycloak_group_roles" "k8s_operators" {
  realm_id = keycloak_realm.broker.id
  group_id = keycloak_group.k8s_operators.id
  role_ids = [keycloak_role.k8s_operator.id]
}

resource "keycloak_group_roles" "web_admins" {
  realm_id = keycloak_realm.broker.id
  group_id = keycloak_group.web_admins.id
  role_ids = [keycloak_role.web_admin.id]
}

resource "keycloak_group_roles" "web_operators" {
  realm_id = keycloak_realm.broker.id
  group_id = keycloak_group.web_operators.id
  role_ids = [keycloak_role.web_operator.id]
}

resource "keycloak_group_roles" "app_users" {
  realm_id = keycloak_realm.broker.id
  group_id = keycloak_group.app_users.id
  role_ids = [keycloak_role.app_user.id]
}
