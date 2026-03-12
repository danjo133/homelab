variable "cluster_name" {
  description = "Name of the cluster (e.g. kss, kcs)"
  type        = string
}

variable "k8s_auth_mount" {
  description = "Vault auth mount path for Kubernetes"
  type        = string
  default     = "kubernetes"
}

# Kubernetes auth config — populated from live cluster data.
# These have sensible defaults so `tofu plan` works without a running cluster;
# real values are set during import or subsequent apply.

variable "k8s_host" {
  description = "Kubernetes API server URL"
  type        = string
  default     = ""
}

variable "k8s_token_reviewer_jwt" {
  description = "Service account JWT for token review"
  type        = string
  default     = ""
  sensitive   = true
}

variable "k8s_ca_cert" {
  description = "Kubernetes cluster CA certificate (PEM)"
  type        = string
  default     = ""
}
