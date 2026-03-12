# Base environment — root-level resources across all services
#
# Manages:
#   - Vault root PKI + namespaces
#   - Upstream Keycloak realm, users, clients
#   - MinIO buckets

module "vault_base" {
  source     = "../../modules/vault-base"
  namespaces = var.vault_namespaces
}

module "keycloak_upstream" {
  source = "../../modules/keycloak-upstream"
}

module "minio_config" {
  source  = "../../modules/minio-config"
  buckets = var.minio_buckets
}

module "gitlab_config" {
  source           = "../../modules/gitlab-config"
  argocd_password  = var.gitlab_argocd_password
  vault_namespaces = var.vault_namespaces
}

module "ziti_config" {
  source           = "../../modules/ziti-config"
  vault_namespaces = var.vault_namespaces

  overlay_services = {
    support-web = {
      intercept_addresses = ["*.support.example.com"]
      intercept_port      = 443
      host_address        = "127.0.0.1"
      bind_roles          = ["support"]
    }
    kss-ingress = {
      intercept_addresses = ["*.simple-k8s.example.com"]
      intercept_port      = 443
      host_address        = "10.69.50.192"
      bind_roles          = ["kss"]
    }
    kcs-ingress = {
      intercept_addresses = ["*.mesh-k8s.example.com"]
      intercept_port      = 443
      host_address        = "10.69.50.209"
      bind_roles          = ["kcs"]
    }
  }

  client_devices = {
    alice-laptop = {}
    bob-phone  = {}
    dave-tablet = {}
  }
}
