# MinIO S3-compatible object storage configuration

{ config, pkgs, lib, ... }:

let
  minioDataDir = "/var/lib/minio/data";
  minioConfigDir = "/etc/minio";
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

  # Ensure directories exist
  systemd.tmpfiles.rules = [
    "d ${minioConfigDir} 0750 minio minio -"
    "d ${minioDataDir} 0750 minio minio -"
  ];

  # Auto-generate credentials on first boot
  systemd.services.minio-init-credentials = {
    description = "Initialize MinIO root credentials";
    wantedBy = [ "minio.service" ];
    before = [ "minio.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.openssl ];
    script = ''
      if [ ! -f ${credentialsFile} ]; then
        echo "Generating MinIO root credentials..."
        MINIO_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)
        cat > ${credentialsFile} << EOF
      MINIO_ROOT_USER=admin
      MINIO_ROOT_PASSWORD=$MINIO_PASSWORD
      EOF
        chmod 600 ${credentialsFile}
        chown minio:minio ${credentialsFile}
        echo "MinIO credentials written to ${credentialsFile}"
      else
        echo "MinIO credentials already exist"
      fi
    '';
  };

  # Note: Firewall rules not needed for MinIO ports as Nginx proxies traffic
  # Access is via:
  # - https://minio.support.example.com (API)
  # - https://minio-console.support.example.com (Console)
}
