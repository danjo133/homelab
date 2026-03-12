# Harbor container registry configuration
# Harbor runs via Docker Compose managed by systemd
# Auto-installs on first boot

{ config, pkgs, lib, ... }:

let
  harborDir = "/opt/harbor";
  harborDataDir = "/var/lib/harbor";
  harborVersion = "v2.14.2";
  harborInstallerUrl = "https://github.com/goharbor/harbor/releases/download/${harborVersion}/harbor-offline-installer-${harborVersion}.tgz";

  # Harbor auto-setup script
  harborAutoSetup = pkgs.writeShellScript "harbor-auto-setup" ''
    set -eu

    export PATH="${pkgs.curl}/bin:${pkgs.gnutar}/bin:${pkgs.gzip}/bin:${pkgs.openssl}/bin:${pkgs.docker-compose}/bin:${pkgs.docker}/bin:${pkgs.gawk}/bin:${pkgs.gnugrep}/bin:${pkgs.gnused}/bin:${pkgs.coreutils}/bin:${pkgs.findutils}/bin:${pkgs.minio-client}/bin:$PATH"
    export HOME=/tmp

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

_version: 2.14.2

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

      # Ensure the harbor bucket exists in MinIO
      mc alias set local http://127.0.0.1:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" --quiet
      mc mb local/harbor --ignore-existing --quiet
      echo "MinIO 'harbor' bucket ready"

      # Use the support VM's stable IP so Docker containers can reach MinIO.
      # MinIO listens on 0.0.0.0:9000 and port 9000 is open in the firewall,
      # so traffic from the Harbor bridge network reaches the host via INPUT.
      cat >> "$HARBOR_DIR/harbor.yml" << MINIOEOF

storage_service:
  s3:
    accesskey: $MINIO_ROOT_USER
    secretkey: $MINIO_ROOT_PASSWORD
    region: us-east-1
    bucket: harbor
    regionendpoint: http://10.69.50.10:9000
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

  # Harbor proxy cache setup script - creates registry endpoints and proxy cache projects
  harborProxyCacheSetup = pkgs.writeShellScript "harbor-proxy-cache-setup" ''
    set -eu

    export PATH="${pkgs.curl}/bin:${pkgs.jq}/bin:${pkgs.coreutils}/bin:$PATH"

    HARBOR_URL="http://127.0.0.1:8080"
    HARBOR_API="$HARBOR_URL/api/v2.0"
    HARBOR_ADMIN_PASSWORD=$(cat /etc/harbor/admin_password)
    AUTH="admin:$HARBOR_ADMIN_PASSWORD"
    MARKER="${harborDir}/.proxy-caches-complete"

    if [ -f "$MARKER" ]; then
      echo "Harbor proxy caches already configured"
      exit 0
    fi

    # Wait for Harbor API to be ready
    echo "==> Waiting for Harbor API..."
    for i in $(seq 1 60); do
      if curl -sf "$HARBOR_API/systeminfo" -u "$AUTH" >/dev/null 2>&1; then
        echo "Harbor API is ready"
        break
      fi
      if [ "$i" -eq 60 ]; then
        echo "ERROR: Harbor API not ready after 120s"
        exit 1
      fi
      sleep 2
    done

    # Helper: create a registry endpoint if it doesn't exist
    create_registry() {
      local name="$1" type="$2" url="$3"
      if curl -sf "$HARBOR_API/registries" -u "$AUTH" | jq -e ".[] | select(.name == \"$name\")" >/dev/null 2>&1; then
        echo "  Registry endpoint '$name' already exists"
      else
        echo "  Creating registry endpoint '$name' -> $url"
        curl -sf -X POST "$HARBOR_API/registries" -u "$AUTH" \
          -H 'Content-Type: application/json' \
          -d "{\"name\": \"$name\", \"type\": \"$type\", \"url\": \"$url\", \"insecure\": false}" \
          || { echo "ERROR: Failed to create registry '$name'"; return 1; }
      fi
    }

    # Helper: create a proxy cache project if it doesn't exist
    create_proxy_project() {
      local project_name="$1" registry_name="$2"
      if curl -sf "$HARBOR_API/projects" -u "$AUTH" | jq -e ".[] | select(.name == \"$project_name\")" >/dev/null 2>&1; then
        echo "  Project '$project_name' already exists"
      else
        # Look up registry ID
        local reg_id
        reg_id=$(curl -sf "$HARBOR_API/registries" -u "$AUTH" | jq -r ".[] | select(.name == \"$registry_name\") | .id")
        if [ -z "$reg_id" ] || [ "$reg_id" = "null" ]; then
          echo "ERROR: Registry '$registry_name' not found"
          return 1
        fi
        echo "  Creating proxy cache project '$project_name' (registry id=$reg_id)"
        curl -sf -X POST "$HARBOR_API/projects" -u "$AUTH" \
          -H 'Content-Type: application/json' \
          -d "{
            \"project_name\": \"$project_name\",
            \"public\": true,
            \"registry_id\": $reg_id,
            \"metadata\": {\"public\": \"true\"}
          }" \
          || { echo "ERROR: Failed to create project '$project_name'"; return 1; }
      fi
    }

    echo "==> Creating registry endpoints..."
    create_registry "docker-hub"  "docker-hub"    "https://hub.docker.com"
    create_registry "ghcr"        "github-ghcr"   "https://ghcr.io"
    create_registry "quay"        "quay"          "https://quay.io"

    echo "==> Creating proxy cache projects..."
    create_proxy_project "docker.io"       "docker-hub"
    create_proxy_project "ghcr.io"         "ghcr"
    create_proxy_project "quay.io"         "quay"

    touch "$MARKER"
    echo "==> Harbor proxy caches configured successfully"
  '';

  # Harbor apps project setup — creates apps project, gcr.io proxy cache, and robot accounts
  harborAppsProjectSetup = pkgs.writeShellScript "harbor-apps-project-setup" ''
    set -eu

    export PATH="${pkgs.curl}/bin:${pkgs.jq}/bin:${pkgs.coreutils}/bin:$PATH"

    HARBOR_URL="http://127.0.0.1:8080"
    HARBOR_API="$HARBOR_URL/api/v2.0"
    HARBOR_ADMIN_PASSWORD=$(cat /etc/harbor/admin_password)
    AUTH="admin:$HARBOR_ADMIN_PASSWORD"
    MARKER="${harborDir}/.apps-project-complete"
    VAULT_ADDR="http://127.0.0.1:8200"
    KEYS_FILE="/var/lib/openbao/init-keys.json"

    if [ -f "$MARKER" ]; then
      echo "Harbor apps project already configured"
      exit 0
    fi

    # Wait for Harbor API to be ready
    echo "==> Waiting for Harbor API..."
    for i in $(seq 1 60); do
      if curl -sf "$HARBOR_API/systeminfo" -u "$AUTH" >/dev/null 2>&1; then
        echo "Harbor API is ready"
        break
      fi
      if [ "$i" -eq 60 ]; then
        echo "ERROR: Harbor API not ready after 120s"
        exit 1
      fi
      sleep 2
    done

    # --- gcr.io proxy cache ---
    echo "==> Creating gcr.io registry endpoint..."
    if curl -sf "$HARBOR_API/registries" -u "$AUTH" | jq -e '.[] | select(.name == "gcr")' >/dev/null 2>&1; then
      echo "  Registry endpoint 'gcr' already exists"
    else
      echo "  Creating registry endpoint 'gcr' -> https://gcr.io"
      curl -sf -X POST "$HARBOR_API/registries" -u "$AUTH" \
        -H 'Content-Type: application/json' \
        -d '{"name": "gcr", "type": "docker-registry", "url": "https://gcr.io", "insecure": false}' \
        || { echo "ERROR: Failed to create registry 'gcr'"; exit 1; }
    fi

    echo "==> Creating gcr.io proxy cache project..."
    if curl -sf "$HARBOR_API/projects" -u "$AUTH" | jq -e '.[] | select(.name == "gcr.io")' >/dev/null 2>&1; then
      echo "  Project 'gcr.io' already exists"
    else
      REG_ID=$(curl -sf "$HARBOR_API/registries" -u "$AUTH" | jq -r '.[] | select(.name == "gcr") | .id')
      if [ -z "$REG_ID" ] || [ "$REG_ID" = "null" ]; then
        echo "ERROR: Registry 'gcr' not found"
        exit 1
      fi
      echo "  Creating proxy cache project 'gcr.io' (registry id=$REG_ID)"
      curl -sf -X POST "$HARBOR_API/projects" -u "$AUTH" \
        -H 'Content-Type: application/json' \
        -d "{
          \"project_name\": \"gcr.io\",
          \"public\": true,
          \"registry_id\": $REG_ID,
          \"metadata\": {\"public\": \"true\"}
        }" \
        || { echo "ERROR: Failed to create project 'gcr.io'"; exit 1; }
    fi

    # --- apps project (regular, not proxy cache) ---
    echo "==> Creating apps project..."
    if curl -sf "$HARBOR_API/projects" -u "$AUTH" | jq -e '.[] | select(.name == "apps")' >/dev/null 2>&1; then
      echo "  Project 'apps' already exists"
    else
      curl -sf -X POST "$HARBOR_API/projects" -u "$AUTH" \
        -H 'Content-Type: application/json' \
        -d '{"project_name": "apps", "public": false, "metadata": {"public": "false"}}' \
        || { echo "ERROR: Failed to create project 'apps'"; exit 1; }
    fi

    # --- Robot accounts ---
    # Look up apps project ID
    APPS_PROJECT_ID=$(curl -sf "$HARBOR_API/projects" -u "$AUTH" | jq -r '.[] | select(.name == "apps") | .project_id')
    if [ -z "$APPS_PROJECT_ID" ] || [ "$APPS_PROJECT_ID" = "null" ]; then
      echo "ERROR: Could not find apps project ID"
      exit 1
    fi

    # Helper: create or recreate robot account
    # Deletes existing robot first (secrets can't be retrieved after creation)
    # Outputs only JSON to stdout (for capture), status messages go to stderr
    create_robot() {
      local robot_name="$1" robot_desc="$2"
      shift 2
      local permissions="$1"

      # Delete existing robot if present (project-level robots endpoint)
      local existing_id
      existing_id=$(curl -sf "$HARBOR_API/projects/apps/robots" -u "$AUTH" \
        | jq -r ".[] | select(.name == \"robot\$apps+$robot_name\") | .id")
      if [ -n "$existing_id" ] && [ "$existing_id" != "null" ]; then
        echo "  Deleting existing robot 'robot\$apps+$robot_name' (id=$existing_id) for re-creation..." >&2
        curl -sf -X DELETE "$HARBOR_API/robots/$existing_id" -u "$AUTH" || true
      fi

      echo "  Creating robot account 'robot\$apps+$robot_name'..." >&2
      local RESULT
      RESULT=$(curl -sf -X POST "$HARBOR_API/robots" -u "$AUTH" \
        -H 'Content-Type: application/json' \
        -d "{
          \"name\": \"$robot_name\",
          \"description\": \"$robot_desc\",
          \"duration\": -1,
          \"level\": \"project\",
          \"permissions\": [{
            \"kind\": \"project\",
            \"namespace\": \"apps\",
            \"access\": $permissions
          }]
        }")

      if ! echo "$RESULT" | jq -r '.name' >/dev/null 2>&1; then
        echo "ERROR: Failed to create robot '$robot_name': $RESULT" >&2
        return 1
      fi
      echo "$RESULT"
    }

    echo "==> Creating robot accounts..."

    # Push robot: can push, pull, list repositories and tags
    PUSH_RESULT=$(create_robot "push" "CI push account for apps images" \
      '[{"resource":"repository","action":"push"},{"resource":"repository","action":"pull"},{"resource":"repository","action":"list"},{"resource":"tag","action":"create"},{"resource":"tag","action":"list"}]')

    # Pull robot: can only pull and list
    PULL_RESULT=$(create_robot "pull" "Pull account for apps images" \
      '[{"resource":"repository","action":"pull"},{"resource":"repository","action":"list"},{"resource":"tag","action":"list"}]')

    # --- Store credentials in Vault ---
    if [ -f "$KEYS_FILE" ]; then
      ROOT_TOKEN=$(jq -r '.root_token' "$KEYS_FILE")

      # Extract credentials from robot creation results (only if they contain secret)
      PUSH_NAME=$(echo "$PUSH_RESULT" | jq -r '.name // empty')
      PUSH_SECRET=$(echo "$PUSH_RESULT" | jq -r '.secret // empty')
      PULL_NAME=$(echo "$PULL_RESULT" | jq -r '.name // empty')
      PULL_SECRET=$(echo "$PULL_RESULT" | jq -r '.secret // empty')

      for VAULT_NS in kss kcs; do
        if [ -n "$PUSH_NAME" ] && [ -n "$PUSH_SECRET" ]; then
          curl -sf -X POST \
            -H "X-Vault-Token: $ROOT_TOKEN" \
            -H "X-Vault-Namespace: $VAULT_NS" \
            -H "Content-Type: application/json" \
            -d "$(jq -n --arg user "$PUSH_NAME" --arg pass "$PUSH_SECRET" '{data: {username: $user, password: $pass}}')" \
            "$VAULT_ADDR/v1/secret/data/harbor/apps-push"
          echo "  Stored harbor/apps-push in $VAULT_NS"
        fi

        if [ -n "$PULL_NAME" ] && [ -n "$PULL_SECRET" ]; then
          curl -sf -X POST \
            -H "X-Vault-Token: $ROOT_TOKEN" \
            -H "X-Vault-Namespace: $VAULT_NS" \
            -H "Content-Type: application/json" \
            -d "$(jq -n --arg user "$PULL_NAME" --arg pass "$PULL_SECRET" '{data: {username: $user, password: $pass}}')" \
            "$VAULT_ADDR/v1/secret/data/harbor/apps-pull"
          echo "  Stored harbor/apps-pull in $VAULT_NS"
        fi
      done
    fi

    touch "$MARKER"
    echo "==> Harbor apps project configured successfully"
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

  # Harbor proxy cache setup - creates registry mirrors after Harbor is running
  systemd.services.harbor-proxy-caches = {
    description = "Harbor Proxy Cache Configuration";
    requires = [ "harbor-setup.service" ];
    after = [ "harbor-setup.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = harborProxyCacheSetup;
      TimeoutStartSec = "5min";
    };

    unitConfig = {
      StartLimitIntervalSec = 0;
    };
  };

  # Harbor apps project setup - creates apps project, robot accounts, stores creds in Vault
  systemd.services.harbor-apps-project = {
    description = "Harbor Apps Project and Robot Accounts";
    requires = [ "harbor-proxy-caches.service" ];
    after = [ "harbor-proxy-caches.service" "openbao-init.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = harborAppsProjectSetup;
      TimeoutStartSec = "5min";
    };

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
