# Root-level Vault (no namespace) — for writing DT API key to cluster namespaces
provider "vault" {
  address = var.vault_addr
  token   = var.vault_token

  skip_child_token = true
}

# Dependency-Track on target cluster
# Bootstrap: run `just dtrack-bootstrap` first, then set TF_VAR_dependencytrack_api_key
provider "dependencytrack" {
  host = var.dependencytrack_url
  key  = var.dependencytrack_api_key
}
