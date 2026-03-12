# MinIO S3-compatible object storage configuration

{ config, pkgs, lib, ... }:

let
  deployConfig = import ../generated-config.nix;
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
    listenAddress = "0.0.0.0:9000";
    consoleAddress = "127.0.0.1:9001";
  };

  # Additional MinIO configuration via environment
  systemd.services.minio.environment = {
    # Use path-style URLs
    MINIO_DOMAIN = "minio.${deployConfig.domain}";
    # Browser redirect
    MINIO_BROWSER_REDIRECT_URL = "https://minio-console.${deployConfig.domain}";
  };

  # Ensure directories exist with correct ownership
  # 'Z' rule recursively fixes ownership (handles buckets created by OpenTofu as root)
  systemd.tmpfiles.rules = [
    "d ${minioConfigDir} 0750 minio minio -"
    "d ${minioDataDir} 0750 minio minio -"
    "Z ${minioDataDir} 0750 minio minio -"
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

  # MinIO API listens on 0.0.0.0 so Harbor's Docker containers can reach it
  # via the bridge gateway. Port 9000 must be open in the firewall for this.
  networking.firewall.allowedTCPPorts = [ 9000 ];
}
