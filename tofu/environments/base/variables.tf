# --- Vault ---

variable "vault_addr" {
  description = "Vault server URL"
  type        = string
  default     = "https://vault.support.example.com"
}

variable "vault_token" {
  description = "Vault root token"
  type        = string
  sensitive   = true
}

# --- Keycloak ---

variable "keycloak_url" {
  description = "Keycloak server URL"
  type        = string
  default     = "https://idp.support.example.com"
}

variable "keycloak_admin_user" {
  description = "Keycloak admin username"
  type        = string
  default     = "admin"
}

variable "keycloak_admin_password" {
  description = "Keycloak admin password"
  type        = string
  sensitive   = true
}

# --- MinIO ---

variable "minio_endpoint" {
  description = "MinIO server endpoint (host:port)"
  type        = string
  default     = "minio.support.example.com"
}

variable "minio_access_key" {
  description = "MinIO access key"
  type        = string
  sensitive   = true
}

variable "minio_secret_key" {
  description = "MinIO secret key"
  type        = string
  sensitive   = true
}

variable "minio_ssl" {
  description = "Use SSL for MinIO"
  type        = bool
  default     = true
}

# --- GitLab ---

variable "gitlab_url" {
  description = "GitLab server URL"
  type        = string
  default     = "https://gitlab.support.example.com"
}

variable "gitlab_token" {
  description = "GitLab personal access token (admin)"
  type        = string
  sensitive   = true
}

variable "gitlab_argocd_password" {
  description = "Password for the ArgoCD GitLab service user"
  type        = string
  sensitive   = true
}

# --- OpenZiti ---

variable "ziti_api_url" {
  description = "Ziti controller management API URL"
  type        = string
  default     = "https://z.example.com:2029/edge/management/v1"
}

variable "ziti_admin_user" {
  description = "Ziti admin username"
  type        = string
  default     = "admin"
}

variable "ziti_admin_password" {
  description = "Ziti admin password"
  type        = string
  sensitive   = true
}

# --- Teleport ---

variable "teleport_addr" {
  description = "Teleport proxy address"
  type        = string
  default     = "teleport.support.example.com:3080"
}

variable "teleport_identity_file_path" {
  description = "Path to Teleport identity file for terraform provider"
  type        = string
  sensitive   = true
}

# --- Harbor ---

variable "harbor_url" {
  description = "Harbor server URL"
  type        = string
  default     = "https://harbor.example.com"
}

variable "harbor_admin_user" {
  description = "Harbor admin username"
  type        = string
  default     = "admin"
}

variable "harbor_admin_password" {
  description = "Harbor admin password"
  type        = string
  sensitive   = true
}

# --- Cloudflare ---

variable "cloudflare_api_token" {
  description = "Cloudflare API token for DNS management (from SOPS)"
  type        = string
  sensitive   = true
}

# --- GitLab ---

variable "gitlab_admin_password" {
  description = "GitLab root admin password (from support VM)"
  type        = string
  sensitive   = true
}

# --- Teleport ---

variable "teleport_admin_password" {
  description = "Teleport admin password (from support VM)"
  type        = string
  sensitive   = true
}

# --- SSH ---

variable "admin_ssh_public_key_file" {
  description = "Path to SSH public key for GitLab push access"
  type        = string
  default     = "~/.ssh/kss.pub"
}

# --- Domains ---

variable "base_domain" {
  description = "Base domain for services (e.g. example.com)"
  type        = string
  default     = "example.com"
}

variable "support_domain" {
  description = "Support services subdomain (e.g. support.example.com)"
  type        = string
  default     = "support.example.com"
}

variable "email_domain" {
  description = "Email domain for service accounts and test users (e.g. example.com)"
  type        = string
  default     = "example.com"
}

variable "cluster_names" {
  description = "List of cluster names for constructing broker redirect URIs"
  type        = list(string)
  default     = ["kss", "kcs"]
}

variable "extra_users" {
  description = "Additional Keycloak upstream users from config.yaml"
  type = list(object({
    username   = string
    email      = string
    first_name = string
    last_name  = string
    role       = string
  }))
  default = []
}

variable "ziti_client_devices" {
  description = "Ziti client device identities from config.yaml"
  type = map(object({
    role_attributes = optional(list(string), ["user"])
  }))
  default = {}
}

# --- Module configuration ---

variable "vault_namespaces" {
  description = "Vault namespaces to create"
  type        = list(string)
  default     = ["kss", "kcs"]
}

variable "minio_buckets" {
  description = "MinIO buckets to manage"
  type        = list(string)
  default     = ["harbor", "loki-kss", "loki-kcs", "tofu-state"]
}
