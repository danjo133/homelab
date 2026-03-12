# Vault scoped to kss namespace
provider "vault" {
  address   = var.vault_addr
  token     = var.vault_token
  namespace = "kss"

  skip_child_token = true
}

# Harbor on support VM
provider "harbor" {
  url      = var.harbor_url
  username = var.harbor_admin_user
  password = var.harbor_admin_password
}

# Broker Keycloak on kss cluster
provider "keycloak" {
  client_id = "admin-cli"
  username  = var.broker_admin_user
  password  = var.broker_admin_password
  url       = "https://auth.simple-k8s.example.com"
}
