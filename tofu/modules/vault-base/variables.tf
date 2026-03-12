variable "namespaces" {
  description = "List of Vault namespaces to create (one per cluster)"
  type        = list(string)
  default     = ["kss", "kcs"]
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
