# Harbor container registry configuration
# Harbor runs via Docker Compose managed by systemd
# Auto-installs on first boot

{ config, pkgs, lib, ... }:

let
  harborDir = "/opt/harbor";
  harborDataDir = "/var/lib/harbor";
  harborVersion = "v2.11.0";
  harborInstallerUrl = "https://github.com/goharbor/harbor/releases/download/${harborVersion}/harbor-offline-installer-${harborVersion}.tgz";

  # Harbor auto-setup script
  harborAutoSetup = pkgs.writeShellScript "harbor-auto-setup" ''
    set -eu

    export PATH="${pkgs.curl}/bin:${pkgs.gnutar}/bin:${pkgs.gzip}/bin:${pkgs.openssl}/bin:${pkgs.docker-compose}/bin:${pkgs.docker}/bin:${pkgs.gawk}/bin:${pkgs.gnugrep}/bin:${pkgs.gnused}/bin:${pkgs.coreutils}/bin:${pkgs.findutils}/bin:${pkgs.python3}/bin:$PATH"

    HARBOR_DIR="${harborDir}"
    HARBOR_DATA_DIR="${harborDataDir}"
    HARBOR_VERSION="${harborVersion}"
    HARBOR_INSTALLER_URL="${harborInstallerUrl}"
    HARBOR_ADMIN_PASSWORD_FILE="/etc/harbor/admin_password"
    MINIO_CREDS="/etc/minio/credentials"
    SETUP_MARKER="${harborDir}/.setup-complete"

    echo "==> Harbor Auto-Setup"

    # Check if already set up
    if [ -f "$SETUP_MARKER" ]; then
      echo "Harbor already installed, starting containers..."
      cd "$HARBOR_DIR"
      docker-compose up -d
      echo "Harbor started"
      exit 0
    fi

    # Wait for Docker to be ready
    echo "Waiting for Docker..."
    for i in $(seq 1 30); do
      if docker info >/dev/null 2>&1; then
        echo "Docker is ready"
        break
      fi
      echo "  Attempt $i/30..."
      sleep 2
    done

    # Check if Harbor installer exists, download if not
    if [ ! -f "$HARBOR_DIR/install.sh" ]; then
      echo "==> Downloading Harbor ${harborVersion}..."
      mkdir -p "$HARBOR_DIR"
      cd /tmp
      curl -fsSL "$HARBOR_INSTALLER_URL" -o harbor-installer.tgz
      echo "==> Extracting Harbor..."
      tar xzf harbor-installer.tgz
      cp -r harbor/* "$HARBOR_DIR/"
      rm -rf harbor harbor-installer.tgz
    fi

    # Generate admin password if not exists
    if [ ! -f "$HARBOR_ADMIN_PASSWORD_FILE" ]; then
      mkdir -p /etc/harbor
      openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16 > "$HARBOR_ADMIN_PASSWORD_FILE"
      chmod 600 "$HARBOR_ADMIN_PASSWORD_FILE"
    fi
    HARBOR_ADMIN_PASSWORD=$(cat "$HARBOR_ADMIN_PASSWORD_FILE")

    # Generate database password (stable per install)
    DB_PASSWORD_FILE="/etc/harbor/db_password"
    if [ ! -f "$DB_PASSWORD_FILE" ]; then
      openssl rand -hex 16 > "$DB_PASSWORD_FILE"
      chmod 600 "$DB_PASSWORD_FILE"
    fi
    DB_PASSWORD=$(cat "$DB_PASSWORD_FILE")

    # Generate secret key (stable per install)
    SECRET_KEY_FILE="/etc/harbor/secret_key"
    if [ ! -f "$SECRET_KEY_FILE" ]; then
      openssl rand -hex 16 > "$SECRET_KEY_FILE"
      chmod 600 "$SECRET_KEY_FILE"
    fi
    SECRET_KEY=$(cat "$SECRET_KEY_FILE")

    echo "==> Generating harbor.yml..."

    # Base configuration
    cat > "$HARBOR_DIR/harbor.yml" << HARBOREOF
# Harbor Configuration - Auto-generated
hostname: harbor.support.example.com

# HTTP only - Nginx handles TLS termination
http:
  port: 8080

harbor_admin_password: $HARBOR_ADMIN_PASSWORD

database:
  password: $DB_PASSWORD
  max_idle_conns: 100
  max_open_conns: 900
  conn_max_lifetime: 5m
  conn_max_idle_time: 0

data_volume: $HARBOR_DATA_DIR

trivy:
  ignore_unfixed: false
  skip_update: false
  skip_java_db_update: false
  offline_scan: false
  security_check: vuln
  insecure: false
  timeout: 5m0s

jobservice:
  max_job_workers: 10
  job_loggers:
    - STD_OUTPUT
    - FILE
  logger_sweeper_duration: 1

notification:
  webhook_job_max_retry: 3
  webhook_job_http_client_timeout: 3

log:
  level: info
  local:
    rotate_count: 50
    rotate_size: 200M
    location: /var/log/harbor

_version: 2.11.0

secret_key: $SECRET_KEY

external_url: https://harbor.support.example.com

metric:
  enabled: true
  port: 9090
  path: /metrics
HARBOREOF

    # Add MinIO storage if credentials exist
    if [ -f "$MINIO_CREDS" ]; then
      echo "==> Configuring MinIO storage backend..."
      source "$MINIO_CREDS"
      cat >> "$HARBOR_DIR/harbor.yml" << MINIOEOF

storage_service:
  s3:
    accesskey: $MINIO_ROOT_USER
    secretkey: $MINIO_ROOT_PASSWORD
    region: us-east-1
    bucket: harbor
    regionendpoint: http://127.0.0.1:9000
    secure: false
    v4auth: true
    chunksize: 5242880
    rootdirectory: /
MINIOEOF
    fi

    # Create data directory
    mkdir -p "$HARBOR_DATA_DIR"
    mkdir -p /var/log/harbor

    # Create /bin/bash symlink for Harbor scripts (they hardcode /bin/bash)
    if [ ! -e /bin/bash ]; then
      mkdir -p /bin
      ln -sf ${pkgs.bash}/bin/bash /bin/bash
    fi

    # Run Harbor installer
    echo "==> Running Harbor installer..."
    cd "$HARBOR_DIR"
    ./install.sh --with-trivy

    # Mark setup as complete
    touch "$SETUP_MARKER"

    echo ""
    echo "==> Harbor installation complete!"
    echo "    URL: https://harbor.support.example.com"
    echo "    Username: admin"
    echo "    Password: $HARBOR_ADMIN_PASSWORD"
  '';
in
{
  # Enable Docker for Harbor
  virtualisation.docker = {
    enable = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  # Required packages
  environment.systemPackages = with pkgs; [
    docker-compose
    curl
  ];

  # Harbor auto-setup service - downloads and configures Harbor on first boot
  systemd.services.harbor-setup = {
    description = "Harbor Container Registry Auto-Setup";
    requires = [ "docker.service" "minio.service" ];
    after = [ "docker.service" "network-online.target" "minio.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = harborAutoSetup;
      TimeoutStartSec = "10min";  # Harbor download and install can take a while
    };

    # Don't fail the boot if Harbor setup fails
    unitConfig = {
      StartLimitIntervalSec = 0;
    };
  };

  # Ensure directories exist
  systemd.tmpfiles.rules = [
    "d ${harborDir} 0755 root root -"
    "d ${harborDataDir} 0755 root root -"
    "d /etc/harbor 0755 root root -"
    "d /var/log/harbor 0755 root root -"
  ];

  # Open firewall for Harbor metrics (Prometheus scraping)
  # Main access is via nginx reverse proxy on 443
  networking.firewall.allowedTCPPorts = [
    9090  # Harbor metrics
  ];

  # Allow vagrant user to run docker commands
  users.users.vagrant.extraGroups = [ "docker" ];
}
