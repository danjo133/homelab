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
    random = {
      source = "hashicorp/random"
    }
  }
}

# ─── Group and Project ───────────────────────────────────────────────────────

resource "gitlab_group" "infra" {
  name             = "infra"
  path             = "infra"
  description      = "Infrastructure repositories"
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

resource "gitlab_project" "homelab" {
  name                   = "homelab"
  namespace_id           = gitlab_group.infra.id
  description            = "Kubernetes homelab infrastructure-as-code (public)"
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
  email             = "argocd@${var.email_domain}"
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

resource "gitlab_project_membership" "argocd_homelab" {
  project      = gitlab_project.homelab.id
  user_id      = gitlab_user.argocd.id
  access_level = "reporter"
}

# ─── Admin Push Access ─────────────────────────────────────────────────────

resource "gitlab_user_sshkey" "admin" {
  count   = var.admin_ssh_public_key != "" ? 1 : 0
  user_id = 1 # root user
  title   = "admin-push"
  key     = var.admin_ssh_public_key
}

# ─── CI/CD Variables ───────────────────────────────────────────────────────

resource "gitlab_project_variable" "harbor_push_user" {
  project   = gitlab_project.kss.id
  key       = "HARBOR_PUSH_USER"
  value     = var.harbor_push_user
  protected = false
  masked    = false
}

resource "gitlab_project_variable" "harbor_push_password" {
  project   = gitlab_project.kss.id
  key       = "HARBOR_PUSH_PASSWORD"
  value     = var.harbor_push_password
  protected = false
  masked    = true
}

resource "gitlab_project_variable" "homelab_harbor_push_user" {
  project   = gitlab_project.homelab.id
  key       = "HARBOR_PUSH_USER"
  value     = var.harbor_push_user
  protected = false
  masked    = false
}

resource "gitlab_project_variable" "homelab_harbor_push_password" {
  project   = gitlab_project.homelab.id
  key       = "HARBOR_PUSH_PASSWORD"
  value     = var.harbor_push_password
  protected = false
  masked    = true
}

resource "gitlab_group_variable" "harbor_registry" {
  group     = gitlab_group.infra.id
  key       = "HARBOR_REGISTRY"
  value     = "harbor.${var.support_domain}"
  protected = false
  masked    = false
}

# ─── Renovate Bot ─────────────────────────────────────────────────────────────

resource "random_password" "renovate" {
  length  = 24
  special = false
}

resource "gitlab_user" "renovate" {
  name              = "Renovate Bot"
  username          = "renovate-bot"
  email             = "renovate@${var.email_domain}"
  password          = random_password.renovate.result
  is_admin          = false
  can_create_group  = false
  skip_confirmation = true
}

# Developer = can create branches and merge requests
resource "gitlab_project_membership" "renovate_homelab" {
  project      = gitlab_project.homelab.id
  user_id      = gitlab_user.renovate.id
  access_level = "developer"
}

resource "gitlab_personal_access_token" "renovate" {
  user_id = gitlab_user.renovate.id
  name    = "renovate-runner"
  scopes  = ["api", "write_repository"]
}

resource "gitlab_project" "renovate_runner" {
  name                   = "renovate-runner"
  namespace_id           = gitlab_group.infra.id
  description            = "Renovate Bot — nightly dependency update scanner"
  visibility_level       = "internal"
  default_branch         = "main"
  initialize_with_readme = true
  shared_runners_enabled = true

  lifecycle { ignore_changes = [initialize_with_readme] }
}

resource "gitlab_repository_file" "renovate_ci" {
  project        = gitlab_project.renovate_runner.id
  file_path      = ".gitlab-ci.yml"
  branch         = "main"
  encoding       = "base64"
  content        = base64encode(templatefile("${path.module}/templates/renovate-ci.yml.tftpl", {
    repositories = jsonencode(var.renovate_repositories)
  }))
  commit_message = "Configure Renovate CI pipeline"

  lifecycle { ignore_changes = [content] }
}

resource "gitlab_project_variable" "renovate_token" {
  project   = gitlab_project.renovate_runner.id
  key       = "RENOVATE_TOKEN"
  value     = gitlab_personal_access_token.renovate.token
  protected = false
  masked    = true
}

resource "gitlab_project_variable" "renovate_github_token" {
  count     = var.github_renovate_token != "" ? 1 : 0
  project   = gitlab_project.renovate_runner.id
  key       = "GITHUB_COM_TOKEN"
  value     = var.github_renovate_token
  protected = false
  masked    = true
}

resource "gitlab_project_variable" "renovate_harbor_push_user" {
  project   = gitlab_project.renovate_runner.id
  key       = "HARBOR_PUSH_USER"
  value     = var.harbor_push_user
  protected = false
  masked    = false
}

resource "gitlab_project_variable" "renovate_harbor_push_password" {
  project   = gitlab_project.renovate_runner.id
  key       = "HARBOR_PUSH_PASSWORD"
  value     = var.harbor_push_password
  protected = false
  masked    = true
}

resource "gitlab_pipeline_schedule" "renovate_nightly" {
  project     = gitlab_project.renovate_runner.id
  description = "Renovate nightly dependency scan"
  ref         = "refs/heads/main"
  cron        = "0 22 * * *"
  active      = true
}

# ─── SSH Known Hosts ─────────────────────────────────────────────────────────

# Fetch current GitLab SSH host keys via ssh-keyscan
data "external" "gitlab_ssh_host_keys" {
  program = ["bash", "-c", "ssh-keyscan -p 2222 gitlab.${var.support_domain} 2>/dev/null | grep -v '^#' | jq -Rs '{known_hosts: .}'"]
}

# Store SSH host keys in Vault for ExternalSecrets → ArgoCD known hosts
resource "vault_kv_secret_v2" "gitlab_ssh_known_hosts" {
  for_each  = toset(var.vault_namespaces)
  namespace = each.value
  mount     = "secret"
  name      = "gitlab/ssh-host-keys"

  data_json = jsonencode({
    known_hosts = data.external.gitlab_ssh_host_keys.result.known_hosts
  })
}

# Store SSH private key in Vault for each cluster namespace
resource "vault_kv_secret_v2" "argocd_ssh_key" {
  for_each  = toset(var.vault_namespaces)
  namespace = each.value
  mount     = "secret"
  name      = "gitlab/argocd-ssh"

  data_json = jsonencode({
    sshPrivateKey = tls_private_key.argocd.private_key_openssh
    url           = "ssh://git@gitlab.${var.support_domain}:2222/infra/homelab.git"
    type          = "git"
  })
}
