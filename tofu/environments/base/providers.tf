# Root-level Vault (no namespace)
provider "vault" {
  address = var.vault_addr
  token   = var.vault_token

  skip_child_token = true
}

# Upstream Keycloak on support VM
provider "keycloak" {
  client_id = "admin-cli"
  username  = var.keycloak_admin_user
  password  = var.keycloak_admin_password
  url       = var.keycloak_url
}

# MinIO on support VM
provider "minio" {
  minio_server   = var.minio_endpoint
  minio_user     = var.minio_access_key
  minio_password = var.minio_secret_key
  minio_ssl      = var.minio_ssl
}

# GitLab CE on support VM
provider "gitlab" {
  base_url = "${var.gitlab_url}/api/v4/"
  token    = var.gitlab_token
}

# OpenZiti controller management API
provider "ziti" {
  username = var.ziti_admin_user
  password = var.ziti_admin_password
  host     = var.ziti_api_url
}

# Teleport auth server
provider "teleport" {
  addr               = var.teleport_addr
  identity_file_path = var.teleport_identity_file_path
}

# Harbor on support VM
provider "harbor" {
  url      = var.harbor_url
  username = var.harbor_admin_user
  password = var.harbor_admin_password
}
