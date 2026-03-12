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
