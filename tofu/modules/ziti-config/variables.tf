variable "vault_namespaces" {
  description = "Vault namespaces to store router enrollment JWTs in"
  type        = list(string)
  default     = ["kss", "kcs"]
}

variable "overlay_services" {
  description = "Services accessible through the Ziti overlay network"
  type = map(object({
    intercept_addresses = list(string)
    intercept_port      = number
    host_address        = string
    host_port           = optional(number)  # defaults to intercept_port
    protocol            = optional(string, "tcp")
    bind_roles          = list(string)
    dial_roles          = optional(list(string), ["clients"])
  }))
}

variable "client_devices" {
  description = "Client device identities for external Ziti access"
  type = map(object({
    role_attributes = optional(list(string), ["clients"])
  }))
  default = {}
}
