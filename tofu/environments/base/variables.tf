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
