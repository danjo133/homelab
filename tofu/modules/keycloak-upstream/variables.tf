variable "email_domain" {
  description = "Email domain for test users (e.g. example.com)"
  type        = string
  default     = "example.com"
}

variable "support_domain" {
  description = "Support services domain (e.g. support.example.com)"
  type        = string
  default     = "support.example.com"
}

variable "extra_users" {
  description = "Additional Keycloak users from config.yaml"
  type = list(object({
    username   = string
    email      = string
    first_name = string
    last_name  = string
    role       = string
  }))
  default = []
}

variable "broker_redirect_uris" {
  description = "Valid redirect URIs for the broker-client OIDC client"
  type        = list(string)
  default = [
    "https://auth.kcs.example.com/realms/broker/broker/upstream/endpoint",
    "https://auth.kss.example.com/realms/broker/broker/upstream/endpoint",
  ]
}
