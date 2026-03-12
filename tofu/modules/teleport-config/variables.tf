variable "vault_namespaces" {
  description = "Vault namespaces to store join tokens in"
  type        = list(string)
  default     = ["kss", "kcs"]
}
