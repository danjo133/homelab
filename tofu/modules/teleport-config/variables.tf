variable "vault_namespaces" {
  description = "Vault namespaces to store join tokens in"
  type        = list(string)
  default     = ["kss", "kcs"]
}

variable "teleport_proxy_addr" {
  description = "Teleport proxy address (host:port) for K8s agent config"
  type        = string
  default     = "teleport.support.example.com:3080"
}
