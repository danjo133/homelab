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
