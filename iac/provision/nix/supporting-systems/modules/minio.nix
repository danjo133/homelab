# MinIO S3-compatible object storage configuration

{ config, pkgs, lib, ... }:

let
  minioDataDir = "/var/lib/minio/data";
  minioConfigDir = "/etc/minio";
  # Credentials file - NOT in Nix store
  # Create this file manually or via bootstrap script:
  # /etc/minio/credentials containing:
  # MINIO_ROOT_USER=admin
  # MINIO_ROOT_PASSWORD=<secure-password>
  credentialsFile = "/etc/minio/credentials";
in
{
  # MinIO service - using the built-in NixOS module
  services.minio = {
    enable = true;
    dataDir = [ minioDataDir ];
    configDir = minioConfigDir;
    rootCredentialsFile = credentialsFile;
    listenAddress = "127.0.0.1:9000";
    consoleAddress = "127.0.0.1:9001";
  };

  # Additional MinIO configuration via environment
  systemd.services.minio.environment = {
    # Use path-style URLs
    MINIO_DOMAIN = "minio.support.example.com";
    # Browser redirect
    MINIO_BROWSER_REDIRECT_URL = "https://minio-console.support.example.com";
  };

  # Ensure credentials file exists (will need to be populated by bootstrap script)
  systemd.tmpfiles.rules = [
    "d ${minioConfigDir} 0750 minio minio -"
    "d ${minioDataDir} 0750 minio minio -"
  ];

  # Note: Firewall rules not needed for MinIO ports as Nginx proxies traffic
  # Access is via:
  # - https://minio.support.example.com (API)
  # - https://minio-console.support.example.com (Console)
}
