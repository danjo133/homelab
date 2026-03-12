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

module "teleport_config" {
  source           = "../../modules/teleport-config"
  vault_namespaces = var.vault_namespaces
}

module "ziti_config" {
  source           = "../../modules/ziti-config"
  vault_namespaces = var.vault_namespaces

  overlay_services = {
    # ── Support VM ─────────────────────────────────────────────────────────────
    support-admin = {
      intercept_addresses = [
        "vault.support.example.com",
        "harbor.support.example.com",
        "minio.support.example.com",
        "minio-console.support.example.com",
        "gitlab.support.example.com",
        "zac.support.example.com",
      ]
      intercept_port = 443
      host_address   = "127.0.0.1"
      bind_roles     = ["support"]
      dial_roles     = ["admin"]
    }
    support-auth = {
      intercept_addresses = [
        "keycloak.support.example.com",
        "idp.support.example.com",
      ]
      intercept_port = 443
      host_address   = "127.0.0.1"
      bind_roles     = ["support"]
      dial_roles     = ["admin", "demo"]
    }

    # ── KSS cluster ───────────────────────────────────────────────────────────
    kss-admin = {
      intercept_addresses = [
        "argocd.simple-k8s.example.com",
        "headlamp.simple-k8s.example.com",
        "longhorn.simple-k8s.example.com",
        "spire-oidc.simple-k8s.example.com",
      ]
      intercept_port = 443
      host_address   = "10.69.50.192"
      bind_roles     = ["kss"]
      dial_roles     = ["admin"]
    }
    kss-general = {
      intercept_addresses = [
        "grafana.simple-k8s.example.com",
        "jit.simple-k8s.example.com",
        "setup.simple-k8s.example.com",
        "architecture.simple-k8s.example.com",
      ]
      intercept_port = 443
      host_address   = "10.69.50.192"
      bind_roles     = ["kss"]
      dial_roles     = ["admin", "demo"]
    }
    kss-public = {
      intercept_addresses = [
        "portal.simple-k8s.example.com",
        "auth.simple-k8s.example.com",
        "oauth2-proxy.simple-k8s.example.com",
        "sl.simple-k8s.example.com",
      ]
      intercept_port = 443
      host_address   = "10.69.50.192"
      bind_roles     = ["kss"]
      dial_roles     = ["admin", "demo", "user"]
    }

    # ── KCS cluster ───────────────────────────────────────────────────────────
    kcs-admin = {
      intercept_addresses = [
        "argocd.mesh-k8s.example.com",
        "headlamp.mesh-k8s.example.com",
        "longhorn.mesh-k8s.example.com",
        "kiali.mesh-k8s.example.com",
        "hubble.mesh-k8s.example.com",
      ]
      intercept_port = 443
      host_address   = "10.69.50.209"
      bind_roles     = ["kcs"]
      dial_roles     = ["admin"]
    }
    kcs-general = {
      intercept_addresses = [
        "grafana.mesh-k8s.example.com",
        "jit.mesh-k8s.example.com",
        "setup.mesh-k8s.example.com",
        "architecture.mesh-k8s.example.com",
      ]
      intercept_port = 443
      host_address   = "10.69.50.209"
      bind_roles     = ["kcs"]
      dial_roles     = ["admin", "demo"]
    }
    kcs-public = {
      intercept_addresses = [
        "portal.mesh-k8s.example.com",
        "auth.mesh-k8s.example.com",
        "oauth2-proxy.mesh-k8s.example.com",
        "sl.mesh-k8s.example.com",
      ]
      intercept_port = 443
      host_address   = "10.69.50.209"
      bind_roles     = ["kcs"]
      dial_roles     = ["admin", "demo", "user"]
    }
  }

  client_devices = {
    alice-laptop = { role_attributes = ["admin"] }
    bob-phone  = { role_attributes = ["demo"] }
    dave-tablet = { role_attributes = ["user"] }
  }
}
