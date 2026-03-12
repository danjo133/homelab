# GitLab CE — Git hosting and CI/CD
# Runs via Docker Compose (like Harbor) with Omnibus image
# Behind nginx reverse proxy, OIDC SSO via Keycloak, MinIO object storage

{ config, pkgs, lib, ... }:

let
  deployConfig = import ../generated-config.nix;
  gitlabDir = "/var/lib/gitlab";
  gitlabImage = "gitlab/gitlab-ce:18.9.0-ce.0";

  # Required upgrade stops for GitLab sequential upgrades.
  # When upgrading across major/minor versions, GitLab requires stopping at
  # specific versions in order. Update this list when changing gitlabImage.
  # See: https://docs.gitlab.com/update/upgrade_paths/
  upgradeStops = [
    "gitlab/gitlab-ce:17.8.7-ce.0"
    "gitlab/gitlab-ce:17.11.7-ce.0"
    "gitlab/gitlab-ce:18.2.8-ce.0"
    "gitlab/gitlab-ce:18.5.5-ce.0"
    "gitlab/gitlab-ce:18.8.4-ce.0"
  ];
  vaultAddr = "http://127.0.0.1:8200";
  keysFile = "/var/lib/openbao/init-keys.json";
  setupMarker = "${gitlabDir}/.setup-complete";

  # GitLab auto-setup script
  gitlabAutoSetup = pkgs.writeShellScript "gitlab-auto-setup" ''
    set -eu

    export PATH="${lib.makeBinPath [
      pkgs.docker-compose pkgs.docker pkgs.openssl pkgs.jq pkgs.curl
      pkgs.coreutils pkgs.minio-client pkgs.gnugrep pkgs.gnused pkgs.gawk
    ]}"
    export HOME=/tmp

    GITLAB_DIR="${gitlabDir}"
    GITLAB_IMAGE="${gitlabImage}"
    SETUP_MARKER="${setupMarker}"
    ADMIN_PASSWORD_FILE="/etc/gitlab/admin_password"
    OIDC_SECRET_FILE="/etc/gitlab/oidc-client-secret"
    MINIO_CREDS="/etc/minio/credentials"
    VAULT_ADDR="${vaultAddr}"
    KEYS_FILE="${keysFile}"
    DEPLOY_DOMAIN="${deployConfig.domain}"
    SUPPORT_IP="${deployConfig.supportIp}"

    echo "==> GitLab Auto-Setup"

    # Helper: write docker-compose.yml for a given image
    write_compose() {
      cat > "$GITLAB_DIR/docker-compose.yml" << COMPOSEEOF
services:
  gitlab:
    image: $1
    container_name: gitlab
    restart: always
    hostname: gitlab.$DEPLOY_DOMAIN
    ports:
      - "8929:8929"
      - "2222:22"
    volumes:
      - $GITLAB_DIR/config:/etc/gitlab
      - $GITLAB_DIR/logs:/var/log/gitlab
      - $GITLAB_DIR/data:/var/opt/gitlab
    shm_size: '256m'
COMPOSEEOF
    }

    # Helper: wait for GitLab to become healthy (up to 20 min)
    wait_healthy() {
      echo "  Waiting for GitLab to become healthy..."
      for i in $(seq 1 120); do
        if docker exec gitlab gitlab-ctl status >/dev/null 2>&1; then
          # Check if rails is responding
          if docker exec gitlab curl -sf http://localhost:8929/-/readiness >/dev/null 2>&1; then
            echo "  GitLab is healthy"
            return 0
          fi
        fi
        echo "  Attempt $i/120 (10s intervals)..."
        sleep 10
      done
      echo "  ERROR: GitLab health check timed out after 20 minutes"
      return 1
    }

    # Helper: generate gitlab.rb configuration
    generate_gitlab_rb() {
      local CONFIG_FILE="$GITLAB_DIR/config/gitlab.rb"

      cat > "$CONFIG_FILE" << GITLABEOF
# GitLab Omnibus Configuration — Auto-generated

external_url 'https://gitlab.$DEPLOY_DOMAIN'

# Nginx: listen on HTTP only, external nginx handles TLS
nginx['listen_port'] = 8929
nginx['listen_https'] = false
nginx['proxy_set_headers'] = {
  "X-Forwarded-Proto" => "https",
  "X-Forwarded-Ssl" => "on"
}

# Git SSH on non-standard port
gitlab_rails['gitlab_shell_ssh_port'] = 2222

# Disable container registry (Harbor is the registry)
registry['enable'] = false
gitlab_rails['registry_enabled'] = false

# Disable Let's Encrypt (external nginx)
letsencrypt['enable'] = false

# Resource tuning for VM
puma['worker_processes'] = 2
sidekiq['concurrency'] = 10

# Disable unnecessary features
gitlab_pages['enable'] = false
prometheus['enable'] = false
alertmanager['enable'] = false
node_exporter['enable'] = false
redis_exporter['enable'] = false
postgres_exporter['enable'] = false
gitlab_exporter['enable'] = false
GITLABEOF

      # Inject secrets (these contain shell variables, so use non-quoted heredoc)
      cat >> "$CONFIG_FILE" << SECRETSEOF

# Secret keys
gitlab_rails['initial_root_password'] = '$ADMIN_PASSWORD'
gitlab_rails['secret_key_base'] = '$SECRET_KEY_BASE'
gitlab_rails['otp_key_base'] = '$OTP_KEY_BASE'
gitlab_rails['db_key_base'] = '$DB_KEY_BASE'
SECRETSEOF

      # Inject OIDC config if secret exists
      if [ -f "$OIDC_SECRET_FILE" ]; then
        OIDC_SECRET=$(cat "$OIDC_SECRET_FILE")
        cat >> "$CONFIG_FILE" << OIDCEOF

# Keycloak OIDC SSO
gitlab_rails['omniauth_enabled'] = true
gitlab_rails['omniauth_allow_single_sign_on'] = ['openid_connect']
gitlab_rails['omniauth_block_auto_created_users'] = false
gitlab_rails['omniauth_providers'] = [
  {
    name: 'openid_connect',
    label: 'Keycloak',
    args: {
      name: 'openid_connect',
      scope: ['openid', 'profile', 'email'],
      response_type: 'code',
      issuer: 'https://idp.$DEPLOY_DOMAIN/realms/upstream',
      client_auth_method: 'query',
      discovery: true,
      uid_field: 'preferred_username',
      pkce: true,
      client_options: {
        identifier: 'gitlab',
        secret: '$OIDC_SECRET',
        redirect_uri: 'https://gitlab.$DEPLOY_DOMAIN/users/auth/openid_connect/callback'
      }
    }
  }
]
OIDCEOF
      fi

      # Inject MinIO object storage config
      if [ -f "$MINIO_CREDS" ]; then
        source "$MINIO_CREDS"
        cat >> "$CONFIG_FILE" << MINIOEOF

# MinIO object storage (consolidated form)
gitlab_rails['object_store']['enabled'] = true
gitlab_rails['object_store']['connection'] = {
  'provider' => 'AWS',
  'aws_access_key_id' => '$MINIO_ROOT_USER',
  'aws_secret_access_key' => '$MINIO_ROOT_PASSWORD',
  'region' => 'us-east-1',
  'endpoint' => 'http://$SUPPORT_IP:9000',
  'path_style' => true
}
gitlab_rails['object_store']['objects']['artifacts'] = { 'bucket' => 'gitlab-artifacts' }
gitlab_rails['object_store']['objects']['lfs'] = { 'bucket' => 'gitlab-lfs' }
gitlab_rails['object_store']['objects']['uploads'] = { 'bucket' => 'gitlab-uploads' }
gitlab_rails['object_store']['objects']['packages'] = { 'bucket' => 'gitlab-packages' }
gitlab_rails['object_store']['objects']['terraform_state'] = { 'bucket' => 'gitlab-terraform' }
gitlab_rails['object_store']['objects']['ci_secure_files'] = { 'bucket' => 'gitlab-ci-secure-files' }
gitlab_rails['object_store']['objects']['dependency_proxy'] = { 'bucket' => 'gitlab-dependency-proxy' }
gitlab_rails['object_store']['objects']['pages'] = { 'bucket' => 'gitlab-pages' }
MINIOEOF
      fi

      chmod 600 "$CONFIG_FILE"
    }

    # If already set up, handle config updates and upgrades
    if [ -f "$SETUP_MARKER" ]; then
      cd "$GITLAB_DIR"

      # Read secrets for gitlab.rb generation
      ADMIN_PASSWORD=$(cat "$ADMIN_PASSWORD_FILE")
      SECRET_KEY_BASE=$(cat /etc/gitlab/secret_key_base)
      OTP_KEY_BASE=$(cat /etc/gitlab/otp_key_base)
      DB_KEY_BASE=$(cat /etc/gitlab/db_key_base)

      # Regenerate gitlab.rb and reconfigure if changed
      OLD_HASH=$(sha256sum "$GITLAB_DIR/config/gitlab.rb" 2>/dev/null | awk '{print $1}')
      generate_gitlab_rb
      NEW_HASH=$(sha256sum "$GITLAB_DIR/config/gitlab.rb" | awk '{print $1}')

      # Detect current data version from the GitLab data directory
      VERSION_FILE="$GITLAB_DIR/data/gitlab-rails/VERSION"
      if [ -f "$VERSION_FILE" ]; then
        DATA_VERSION=$(cat "$VERSION_FILE")
      else
        DATA_VERSION="unknown"
      fi

      # Extract target version from image tag (e.g. "18.8.4" from "gitlab/gitlab-ce:18.8.4-ce.0")
      TARGET_VERSION=$(echo "$GITLAB_IMAGE" | sed 's/.*:\(.*\)-ce\..*/\1/')
      echo "Data version:   $DATA_VERSION"
      echo "Target version: $TARGET_VERSION"

      if [ "$DATA_VERSION" = "$TARGET_VERSION" ]; then
        if [ "$OLD_HASH" != "$NEW_HASH" ]; then
          echo "Config changed, reconfiguring..."
          # Ensure container is running
          if ! docker inspect gitlab --format='{{.State.Running}}' 2>/dev/null | grep -q true; then
            write_compose "$GITLAB_IMAGE"
            docker-compose up -d
            wait_healthy
          fi
          docker exec gitlab gitlab-ctl reconfigure
          echo "GitLab reconfigured"
          exit 0
        fi

        # Container already running at correct version, config unchanged
        if docker inspect gitlab --format='{{.State.Running}}' 2>/dev/null | grep -q true; then
          echo "Already at target version and running, nothing to do"
          exit 0
        fi
        echo "Already at target version, starting..."
        write_compose "$GITLAB_IMAGE"
        docker-compose up -d
        echo "GitLab started"
        exit 0
      fi

      # Walk through required upgrade stops, skipping versions <= current data version
      UPGRADE_STOPS="${builtins.concatStringsSep " " upgradeStops}"
      for STOP_IMAGE in $UPGRADE_STOPS; do
        STOP_VERSION=$(echo "$STOP_IMAGE" | sed 's/.*:\(.*\)-ce\..*/\1/')

        # Skip stops that are at or below current data version
        if printf '%s\n%s\n' "$STOP_VERSION" "$DATA_VERSION" | sort -V | head -1 | grep -qx "$STOP_VERSION"; then
          echo "Skipping $STOP_VERSION (data already at $DATA_VERSION)"
          continue
        fi

        echo "==> Upgrading to $STOP_IMAGE (from $DATA_VERSION)..."
        docker rm -f gitlab 2>/dev/null || true
        write_compose "$STOP_IMAGE"
        docker-compose pull
        docker-compose up -d
        wait_healthy

        # Re-read data version after upgrade
        if [ -f "$VERSION_FILE" ]; then
          DATA_VERSION=$(cat "$VERSION_FILE")
          echo "  Data version now: $DATA_VERSION"
        fi
      done

      # Final upgrade to target
      echo "==> Upgrading to target $GITLAB_IMAGE..."
      docker rm -f gitlab 2>/dev/null || true
      write_compose "$GITLAB_IMAGE"
      docker-compose pull
      docker-compose up -d
      echo "GitLab upgrade complete"
      exit 0
    fi

    # Wait for Docker
    echo "Waiting for Docker..."
    for i in $(seq 1 30); do
      if docker info >/dev/null 2>&1; then
        echo "Docker is ready"
        break
      fi
      echo "  Attempt $i/30..."
      sleep 2
    done

    # Generate admin password if not exists
    mkdir -p /etc/gitlab
    if [ ! -f "$ADMIN_PASSWORD_FILE" ]; then
      openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 20 > "$ADMIN_PASSWORD_FILE"
      chmod 600 "$ADMIN_PASSWORD_FILE"
    fi
    ADMIN_PASSWORD=$(cat "$ADMIN_PASSWORD_FILE")

    # Generate secret key base
    SECRET_KEY_FILE="/etc/gitlab/secret_key_base"
    if [ ! -f "$SECRET_KEY_FILE" ]; then
      openssl rand -hex 64 > "$SECRET_KEY_FILE"
      chmod 600 "$SECRET_KEY_FILE"
    fi
    SECRET_KEY_BASE=$(cat "$SECRET_KEY_FILE")

    # Generate OTP key base
    OTP_KEY_FILE="/etc/gitlab/otp_key_base"
    if [ ! -f "$OTP_KEY_FILE" ]; then
      openssl rand -hex 64 > "$OTP_KEY_FILE"
      chmod 600 "$OTP_KEY_FILE"
    fi
    OTP_KEY_BASE=$(cat "$OTP_KEY_FILE")

    # Generate DB key base
    DB_KEY_FILE="/etc/gitlab/db_key_base"
    if [ ! -f "$DB_KEY_FILE" ]; then
      openssl rand -hex 64 > "$DB_KEY_FILE"
      chmod 600 "$DB_KEY_FILE"
    fi
    DB_KEY_BASE=$(cat "$DB_KEY_FILE")

    # Create MinIO buckets for GitLab
    if [ -f "$MINIO_CREDS" ]; then
      echo "==> Creating MinIO buckets for GitLab..."
      source "$MINIO_CREDS"
      mc alias set local http://127.0.0.1:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" --quiet
      for BUCKET in gitlab-artifacts gitlab-lfs gitlab-uploads gitlab-packages gitlab-backups gitlab-tmp gitlab-terraform gitlab-ci-secure-files gitlab-dependency-proxy gitlab-pages; do
        mc mb "local/$BUCKET" --ignore-existing --quiet
      done
      echo "MinIO buckets ready"
    fi

    # Create data directories
    mkdir -p "$GITLAB_DIR"/{config,logs,data}

    # ========================================================================
    # Generate gitlab.rb configuration
    # ========================================================================
    echo "==> Generating gitlab.rb..."
    generate_gitlab_rb

    # ========================================================================
    # Generate docker-compose.yml
    # ========================================================================
    echo "==> Generating docker-compose.yml..."
    write_compose "$GITLAB_IMAGE"

    # Pull and start
    echo "==> Pulling GitLab image..."
    cd "$GITLAB_DIR"
    docker-compose pull
    echo "==> Starting GitLab..."
    docker-compose up -d

    # NOTE: gitlab/admin credentials are now managed by OpenTofu (convenience namespace).
    # See tofu/environments/base/main.tf — vault_kv_secret_v2.convenience_gitlab_admin

    # Mark setup complete
    touch "$SETUP_MARKER"

    echo ""
    echo "==> GitLab installation complete!"
    echo "    URL: https://gitlab.$DEPLOY_DOMAIN"
    echo "    Username: root"
    echo "    Password: $ADMIN_PASSWORD"
    echo "    SSH: ssh -p 2222 git@gitlab.$DEPLOY_DOMAIN"
  '';
in
{
  # GitLab auto-setup service — downloads and runs GitLab via Docker Compose
  systemd.services.gitlab-setup = {
    description = "GitLab CE Auto-Setup (Docker Compose)";
    requires = [ "docker.service" "minio.service" ];
    after = [ "docker.service" "network-online.target" "minio.service" "keycloak-oidc-secrets.service" ];
    wants = [ "keycloak-oidc-secrets.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = gitlabAutoSetup;
      TimeoutStartSec = "90min";  # Sequential upgrades can take a long time
    };

    unitConfig = {
      StartLimitIntervalSec = 0;
    };
  };

  # Ensure directories exist
  systemd.tmpfiles.rules = [
    "d ${gitlabDir} 0755 root root -"
    "d ${gitlabDir}/config 0755 root root -"
    "d ${gitlabDir}/logs 0755 root root -"
    "d ${gitlabDir}/data 0755 root root -"
    "d /etc/gitlab 0750 root root -"
  ];

  # Open firewall for Git SSH
  # GitLab HTTP is proxied via nginx on 443
  networking.firewall.allowedTCPPorts = [
    2222  # Git SSH
  ];
}
