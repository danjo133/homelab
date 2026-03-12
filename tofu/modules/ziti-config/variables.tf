variable "vault_namespaces" {
  description = "Vault namespaces to store router enrollment JWTs in"
  type        = list(string)
  default     = ["kss", "kcs"]
}

variable "support_services" {
  description = "Support VM services to expose via Ziti"
  type = map(object({
    port              = number
    intercept_address = string
    host_address      = string
    protocol          = optional(string, "tcp")
  }))
}
