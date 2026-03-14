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

# --- Harbor ---

variable "harbor_url" {
  description = "Harbor server URL"
  type        = string
  default     = "https://harbor.support.example.com"
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

# --- Broker Keycloak ---

variable "broker_keycloak_url" {
  description = "Broker Keycloak URL (e.g. https://auth.kcs.example.com)"
  type        = string
  default     = "https://auth.kcs.example.com"
}

variable "broker_admin_user" {
  description = "Broker Keycloak admin username"
  type        = string
  default     = "temp-admin"
}

variable "broker_admin_password" {
  description = "Broker Keycloak admin password"
  type        = string
  sensitive   = true
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

# --- Kubernetes auth (optional — set from live cluster) ---

variable "k8s_host" {
  description = "Kubernetes API server URL"
  type        = string
  default     = ""
}

variable "k8s_token_reviewer_jwt" {
  description = "Service account JWT for Vault token review"
  type        = string
  default     = ""
  sensitive   = true
}

variable "k8s_ca_cert" {
  description = "Kubernetes cluster CA certificate (PEM)"
  type        = string
  default     = ""
}
