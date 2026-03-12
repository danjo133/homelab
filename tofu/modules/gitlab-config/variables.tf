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
