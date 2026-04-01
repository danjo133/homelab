variable "argocd_password" {
  description = "Password for the ArgoCD GitLab service user"
  type        = string
  sensitive   = true
}

variable "vault_namespaces" {
  description = "Vault namespaces to store the SSH key in"
  type        = list(string)
  default     = ["kss", "kcs"]
}

variable "harbor_push_user" {
  description = "Harbor push robot username for CI builds"
  type        = string
  default     = ""
}

variable "harbor_push_password" {
  description = "Harbor push robot secret for CI builds"
  type        = string
  sensitive   = true
  default     = ""
}

variable "admin_ssh_public_key" {
  description = "SSH public key for admin push access (read from ~/.ssh/kss.pub)"
  type        = string
  default     = ""
}

variable "support_domain" {
  description = "Support services domain for GitLab FQDN (e.g. support.example.com)"
  type        = string
  default     = "support.example.com"
}

variable "email_domain" {
  description = "Email domain for service accounts (e.g. example.com)"
  type        = string
  default     = "example.com"
}

variable "gitlab_token" {
  description = "GitLab admin PAT — used to create Renovate user PAT"
  type        = string
  sensitive   = true
  default     = ""
}

variable "github_renovate_token" {
  description = "GitHub PAT for Renovate changelog lookups (optional, reduces rate limiting)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "renovate_repositories" {
  description = "GitLab project paths for Renovate to scan (e.g. [\"infra/homelab\"])"
  type        = list(string)
  default     = ["infra/homelab"]
}
