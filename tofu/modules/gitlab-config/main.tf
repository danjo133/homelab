# GitLab configuration — groups, projects, and service accounts
#
# Manages:
#   - infra group and kss project
#   - ArgoCD service user with SSH key
#   - SSH private key stored in Vault (per-cluster namespace)

terraform {
  required_providers {
    gitlab = {
      source = "gitlabhq/gitlab"
    }
    tls = {
      source = "hashicorp/tls"
    }
    vault = {
      source = "hashicorp/vault"
    }
  }
}

# ─── Group and Project ───────────────────────────────────────────────────────

resource "gitlab_group" "infra" {
  name        = "infra"
  path        = "infra"
  description = "Infrastructure repositories"
  visibility_level = "internal"
}

resource "gitlab_project" "kss" {
  name                   = "kss"
  namespace_id           = gitlab_group.infra.id
  description            = "Kubernetes homelab infrastructure-as-code"
  visibility_level       = "internal"
  default_branch         = "main"
  initialize_with_readme = false

  lifecycle { ignore_changes = [initialize_with_readme] }
}

# ─── ArgoCD Service User ─────────────────────────────────────────────────────

resource "tls_private_key" "argocd" {
  algorithm = "ED25519"
}

resource "gitlab_user" "argocd" {
  name              = "ArgoCD"
  username          = "argocd"
  email             = "argocd@example.com"
  password          = var.argocd_password
  is_admin          = false
  can_create_group  = false
  skip_confirmation = true
}

resource "gitlab_user_sshkey" "argocd" {
  user_id = gitlab_user.argocd.id
  title   = "argocd-deploy"
  key     = tls_private_key.argocd.public_key_openssh
}

# Reporter = read-only access to the project
resource "gitlab_project_membership" "argocd" {
  project      = gitlab_project.kss.id
  user_id      = gitlab_user.argocd.id
  access_level = "reporter"
}

# ─── Vault Storage ───────────────────────────────────────────────────────────

# Store SSH private key in Vault for each cluster namespace
resource "vault_kv_secret_v2" "argocd_ssh_key" {
  for_each  = toset(var.vault_namespaces)
  namespace = each.value
  mount     = "secret"
  name      = "gitlab/argocd-ssh"

  data_json = jsonencode({
    sshPrivateKey = tls_private_key.argocd.private_key_openssh
    url           = "https://github.com/example-user/homelab.git"
    type          = "git"
  })
}
