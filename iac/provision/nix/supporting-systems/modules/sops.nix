# SOPS-nix secrets management
# Fetches sops-nix module and configures secret decryption

{ config, pkgs, lib, ... }:

let
  # Fetch sops-nix from GitHub
  sops-nix = builtins.fetchTarball {
    url = "https://github.com/Mic92/sops-nix/archive/master.tar.gz";
    # Pin to a specific version for reproducibility (update periodically)
    # sha256 = "sha256:0000000000000000000000000000000000000000000000000000";
  };
in
{
  imports = [
    "${sops-nix}/modules/sops"
  ];

  # SOPS configuration
  sops = {
    # Default secrets file location (encrypted with sops)
    defaultSopsFile = ../secrets/secrets.yaml;

    # Use age for encryption with dedicated age key
    age = {
      # Age key file (synced from host ~/.vagrant.d/sops_age_keys.txt)
      keyFile = "/etc/sops/keys/age-keys.txt";
      # Don't auto-generate - we provide our own key
      generateKey = false;
    };

    # Define secrets
    secrets = {
      # Cloudflare API token for ACME
      "cloudflare_api_token" = {
        owner = "root";
        group = "root";
        mode = "0400";
        # Will be available at /run/secrets/cloudflare_api_token
      };

      # Keycloak admin password (read by root services: keycloak-admin-env, keycloak-oidc-secrets)
      "keycloak_admin_password" = {
        owner = "root";
        group = "root";
        mode = "0400";
        # Will be available at /run/secrets/keycloak_admin_password
      };
    };
  };

  # Create directory for sops keys
  systemd.tmpfiles.rules = [
    "d /etc/sops/keys 0700 root root -"
  ];

  # Install sops CLI tool for manual operations
  environment.systemPackages = with pkgs; [
    sops
    age
  ];
}
