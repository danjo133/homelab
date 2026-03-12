terraform {
  required_version = ">= 1.6"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.0"
    }
    harbor = {
      source  = "goharbor/harbor"
      version = "~> 3.10"
    }
  }
}
