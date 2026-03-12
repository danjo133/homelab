# ACME (Let's Encrypt) certificate configuration
#
# OPTIONAL: Import this module to use Let's Encrypt instead of self-signed certs
#
# Prerequisites:
# 1. Import sops.nix and set up sops-nix with your age key
# 2. Create encrypted secrets/secrets.yaml with cloudflare_api_token
# 3. Uncomment this module in configuration.nix
#
# See .sops.yaml at repo root for setup instructions

{ config, pkgs, lib, ... }:

let
  deployConfig = import ../generated-config.nix;
  domain = deployConfig.domain;
  wildcardDomain = "*.${domain}";
in
{
  # ACME (Let's Encrypt) configuration
  security.acme = {
    acceptTerms = true;
    defaults = {
      email = deployConfig.adminEmail;
      dnsProvider = "cloudflare";
      # Use sops-managed secret for Cloudflare credentials
      credentialsFile = config.sops.secrets.cloudflare_api_token.path;
      # Use DNS-01 challenge for wildcard certs
      dnsResolver = "1.1.1.1:53";
    };

    # Wildcard certificate
    certs."${domain}" = {
      domain = domain;
      extraDomainNames = [ wildcardDomain ];
      group = "nginx";
    };
  };

  # Override nginx virtual hosts to use ACME certs instead of self-signed
  services.nginx.virtualHosts = {
    "vault.${domain}" = {
      useACMEHost = domain;
      sslCertificate = lib.mkForce null;
      sslCertificateKey = lib.mkForce null;
    };
    "minio.${domain}" = {
      useACMEHost = domain;
      sslCertificate = lib.mkForce null;
      sslCertificateKey = lib.mkForce null;
    };
    "minio-console.${domain}" = {
      useACMEHost = domain;
      sslCertificate = lib.mkForce null;
      sslCertificateKey = lib.mkForce null;
    };
    "harbor.${domain}" = {
      useACMEHost = domain;
      sslCertificate = lib.mkForce null;
      sslCertificateKey = lib.mkForce null;
    };
    "idp.${domain}" = {
      useACMEHost = domain;
      sslCertificate = lib.mkForce null;
      sslCertificateKey = lib.mkForce null;
    };
    "gitlab.${domain}" = {
      useACMEHost = domain;
      sslCertificate = lib.mkForce null;
      sslCertificateKey = lib.mkForce null;
    };
    "teleport.${domain}" = {
      useACMEHost = domain;
      sslCertificate = lib.mkForce null;
      sslCertificateKey = lib.mkForce null;
    };
    "zac.${domain}" = {
      useACMEHost = domain;
      sslCertificate = lib.mkForce null;
      sslCertificateKey = lib.mkForce null;
    };
  };

  # Disable self-signed cert generation when using ACME
  systemd.services.nginx-cert-gen.enable = lib.mkForce false;
}
