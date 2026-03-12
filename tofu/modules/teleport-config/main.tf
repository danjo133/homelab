# Teleport configuration — provision tokens, roles
#
# Manages:
#   - Per-cluster provision tokens for kube-agent enrollment
#   - RBAC roles (kube-admin, kube-viewer)

# ─── Provision Tokens ─────────────────────────────────────────────────────────

# Random token value per cluster
resource "random_password" "cluster_token" {
  for_each = toset(var.vault_namespaces)
  length   = 32
  special  = false
}

# Provision token for kube-agent enrollment
resource "teleport_provision_token" "cluster" {
  for_each = toset(var.vault_namespaces)
  version  = "v2"

  metadata = {
    name        = random_password.cluster_token[each.key].result
    description = "${each.key} cluster kube-agent join token"
    labels = {
      cluster = each.key
    }
  }

  spec = {
    roles       = ["Kube", "App"]
    join_method = "token"
  }
}

# ─── Roles ────────────────────────────────────────────────────────────────────

# Full K8s + app access
resource "teleport_role" "kube_admin" {
  version = "v7"

  metadata = {
    name = "kube-admin"
  }

  spec = {
    allow = {
      kubernetes_groups = ["system:masters"]
      kubernetes_labels = { "*" = ["*"] }
      app_labels        = { "*" = ["*"] }
      logins            = ["root", "vagrant"]
    }
  }
}

# Read-only K8s + app access
resource "teleport_role" "kube_viewer" {
  version = "v7"

  metadata = {
    name = "kube-viewer"
  }

  spec = {
    allow = {
      kubernetes_groups = ["system:authenticated"]
      kubernetes_labels = { "*" = ["*"] }
      app_labels        = { "*" = ["*"] }
    }
  }
}
