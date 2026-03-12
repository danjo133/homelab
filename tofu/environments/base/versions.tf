terraform {
  required_version = ">= 1.6"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.0"
    }
    keycloak = {
      source  = "keycloak/keycloak"
      version = "~> 5.0"
    }
    minio = {
      source  = "aminueza/minio"
      version = "~> 3.2"
    }
    gitlab = {
      source  = "gitlabhq/gitlab"
      version = "~> 18.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    ziti = {
      source  = "netfoundry/ziti"
      version = "~> 1.0"
    }
    teleport = {
      source  = "terraform.releases.teleport.dev/gravitational/teleport"
      version = "~> 18.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    harbor = {
      source  = "goharbor/harbor"
      version = "~> 3.10"
    }
  }
}
