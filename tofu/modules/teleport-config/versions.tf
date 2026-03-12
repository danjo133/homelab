terraform {
  required_providers {
    teleport = {
      source = "terraform.releases.teleport.dev/gravitational/teleport"
    }
    vault = {
      source = "hashicorp/vault"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}
