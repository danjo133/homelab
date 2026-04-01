terraform {
  required_version = ">= 1.6"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.0"
    }
    dependencytrack = {
      source  = "SolarFactories/dependencytrack"
      version = "~> 1.19"
    }
  }
}
