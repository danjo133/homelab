variable "namespaces" {
  description = "List of Vault namespaces to create (one per cluster)"
  type        = list(string)
  default     = ["kss", "kcs"]
}

variable "vault_fqdn" {
  description = "Vault server FQDN for PKI issuing/CRL URLs (e.g. vault.support.example.com)"
  type        = string
  default     = "vault.support.example.com"
}

variable "broker_client_secret" {
  description = "Upstream broker-client secret to seed into each cluster namespace"
  type        = string
  sensitive   = true
  default     = ""
}

variable "seed_broker_client" {
  description = "Whether to seed the broker-client secret (set true when secret is provided)"
  type        = bool
  default     = false
}
