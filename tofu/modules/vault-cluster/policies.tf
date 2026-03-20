# Vault policies for the cluster namespace

resource "vault_policy" "external_secrets" {
  name = "external-secrets"

  policy = <<-EOT
    # Policy for external-secrets operator — scoped to known secret paths
    path "secret/data/keycloak/*" {
      capabilities = ["read"]
    }
    path "secret/data/oauth2-proxy" {
      capabilities = ["read"]
    }
    path "secret/data/harbor/*" {
      capabilities = ["read"]
    }
    path "secret/data/grafana/*" {
      capabilities = ["read"]
    }
    path "secret/data/minio/*" {
      capabilities = ["read"]
    }
    path "secret/data/cloudflare" {
      capabilities = ["read"]
    }
    path "secret/data/teleport/*" {
      capabilities = ["read"]
    }
    path "secret/data/ziti/*" {
      capabilities = ["read"]
    }
    path "secret/data/open-webui/*" {
      capabilities = ["read"]
    }
    path "secret/data/open-terminal/*" {
      capabilities = ["read"]
    }
    path "secret/data/openclaw/*" {
      capabilities = ["read"]
    }
    path "secret/data/mcpo/*" {
      capabilities = ["read"]
    }
    path "secret/metadata/*" {
      capabilities = ["read", "list"]
    }
  EOT
}

resource "vault_policy" "spiffe_workload" {
  name = "spiffe-workload"

  policy = <<-EOT
    # Allow SPIFFE workloads to read secrets scoped to their namespace
    path "secret/data/workloads/*" {
      capabilities = ["read"]
    }
    # Allow PKI certificate issuance
    path "pki_int/issue/${var.pki_role_name}" {
      capabilities = ["create", "update"]
    }
  EOT
}

resource "vault_policy" "keycloak_operator" {
  name = "keycloak-operator"

  policy = <<-EOT
    path "secret/data/keycloak/*" {
      capabilities = ["read"]
    }
    path "secret/data/oauth2-proxy" {
      capabilities = ["read"]
    }
  EOT
}
