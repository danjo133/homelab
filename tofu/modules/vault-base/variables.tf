variable "namespaces" {
  description = "List of Vault namespaces to create (one per cluster)"
  type        = list(string)
  default     = ["kss", "kcs"]
}
