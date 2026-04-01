# --- Vault ---

variable "vault_addr" {
  description = "Vault server address"
  type        = string
}

variable "vault_token" {
  description = "Vault root or privileged token"
  type        = string
  sensitive   = true
  default     = ""
}

# --- Dependency-Track ---

variable "dependencytrack_url" {
  description = "Dependency-Track API server URL"
  type        = string
}

variable "dependencytrack_api_key" {
  description = "Dependency-Track admin API key (from bootstrap script)"
  type        = string
  sensitive   = true
}

# --- Cluster ---

variable "cluster_name" {
  description = "Cluster name (used as Vault namespace for writing the API key)"
  type        = string
}
