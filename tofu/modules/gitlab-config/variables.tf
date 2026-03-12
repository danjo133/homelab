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
