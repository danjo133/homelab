variable "cluster_name" {
  description = "Cluster name (e.g. kss, kcs)"
  type        = string
}

variable "domain" {
  description = "Cluster domain (e.g. simple-k8s.example.com)"
  type        = string
}

# --- Upstream IdP ---

variable "upstream_issuer" {
  description = "Upstream Keycloak issuer URL"
  type        = string
  default     = "https://idp.support.example.com/realms/upstream"
}

variable "upstream_client_id" {
  description = "Upstream broker-client client ID"
  type        = string
  default     = "broker-client"
}

variable "upstream_client_secret" {
  description = "Upstream broker-client secret"
  type        = string
  sensitive   = true
}

# --- Social identity providers ---

variable "google_client_id" {
  description = "Google OAuth client ID"
  type        = string
}

variable "google_client_secret" {
  description = "Google OAuth client secret"
  type        = string
  sensitive   = true
}

variable "github_client_id" {
  description = "GitHub OAuth client ID"
  type        = string
}

variable "github_client_secret" {
  description = "GitHub OAuth client secret"
  type        = string
  sensitive   = true
}

variable "microsoft_client_id" {
  description = "Microsoft OAuth client ID"
  type        = string
}

variable "microsoft_client_secret" {
  description = "Microsoft OAuth client secret"
  type        = string
  sensitive   = true
}
