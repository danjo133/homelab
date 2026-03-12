# OpenZiti — zero-trust overlay network
# Runs controller + support router via Docker Compose (like GitLab/Harbor)
# Controller handles management/control plane, router hosts support VM services
# Requires TLS passthrough (client cert validation), not behind nginx

{ config, pkgs, lib, ... }:

let
  zitiDir = "/var/lib/ziti";
  controllerDir = "${zitiDir}/controller";
  routerDir = "${zitiDir}/router";
  controllerImage = "openziti/ziti-controller:1.2.2";
  routerImage = "openziti/ziti-router:1.2.2";
  vaultAddr = "http://127.0.0.1:8200";
  keysFile = "/var/lib/openbao/init-keys.json";
  setupMarker = "${controllerDir}/.setup-complete";

  # Controller + router auto-setup script
  zitiAutoSetup = pkgs.writeShellScript "ziti-auto-setup" ''
    set -eu

    export PATH="${lib.makeBinPath [
      pkgs.docker-compose pkgs.docker pkgs.openssl pkgs.jq pkgs.curl
      pkgs.coreutils pkgs.gnugrep
    ]}"
    export HOME=/tmp

    ZITI_DIR="${zitiDir}"
    CONTROLLER_DIR="${controllerDir}"
    ROUTER_DIR="${routerDir}"
    CONTROLLER_IMAGE="${controllerImage}"
    ROUTER_IMAGE="${routerImage}"
    SETUP_MARKER="${setupMarker}"
    ADMIN_PASSWORD_FILE="/etc/ziti/admin_password"
    ROUTER_JWT_FILE="/etc/ziti/support-router.jwt"
    VAULT_ADDR="${vaultAddr}"
    KEYS_FILE="${keysFile}"

    echo "==> OpenZiti Auto-Setup"

    # If already set up, just ensure services are running
    if [ -f "$SETUP_MARKER" ]; then
      echo "OpenZiti already set up, ensuring running..."
      cd "$CONTROLLER_DIR"
      docker-compose up -d
      # Wait for controller to be healthy before starting router
      echo "Waiting for controller health..."
      for i in $(seq 1 40); do
        if docker inspect ziti-controller --format='{{.State.Health.Status}}' 2>/dev/null | grep -q healthy; then
          echo "  Controller is healthy"
          break
        fi
        echo "  Attempt $i/40..."
        sleep 3
      done
      cd "$ROUTER_DIR"
      docker-compose up -d
      echo "OpenZiti services started"
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
    mkdir -p /etc/ziti
    if [ ! -f "$ADMIN_PASSWORD_FILE" ]; then
      openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 20 > "$ADMIN_PASSWORD_FILE"
      chmod 600 "$ADMIN_PASSWORD_FILE"
    fi
    ADMIN_PASSWORD=$(cat "$ADMIN_PASSWORD_FILE")

    # ========================================================================
    # 1. Start Ziti Controller
    # ========================================================================
    echo "==> Starting Ziti Controller..."

    cat > "$CONTROLLER_DIR/docker-compose.yml" << COMPOSEEOF
services:
  chown-controller:
    image: busybox
    command: chown -R 2171 /ziti-controller
    volumes:
      - $CONTROLLER_DIR/data:/ziti-controller
  ziti-controller:
    image: $CONTROLLER_IMAGE
    container_name: ziti-controller
    depends_on:
      chown-controller:
        condition: service_completed_successfully
    user: "2171"
    volumes:
      - $CONTROLLER_DIR/data:/ziti-controller
    environment:
      ZITI_CTRL_ADVERTISED_ADDRESS: ziti.support.example.com
      ZITI_CTRL_ADVERTISED_PORT: "1280"
      ZITI_PWD: "$ADMIN_PASSWORD"
      ZITI_BOOTSTRAP: "true"
      ZITI_BOOTSTRAP_PKI: "true"
      ZITI_BOOTSTRAP_CONFIG: "true"
      ZITI_BOOTSTRAP_DATABASE: "true"
      ZITI_AUTO_RENEW_CERTS: "true"
    command: run config.yml
    ports:
      - "1280:1280"
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "ziti", "agent", "stats"]
      interval: 3s
      timeout: 3s
      retries: 5
      start_period: 30s
COMPOSEEOF

    cd "$CONTROLLER_DIR"
    docker-compose pull
    docker-compose up -d

    # Wait for controller to become healthy
    echo "  Waiting for controller to become healthy..."
    for i in $(seq 1 60); do
      if docker inspect ziti-controller --format='{{.State.Health.Status}}' 2>/dev/null | grep -q healthy; then
        echo "  Controller is healthy"
        break
      fi
      if [ "$i" = "60" ]; then
        echo "  ERROR: Controller health check timed out"
        exit 1
      fi
      echo "  Attempt $i/60 (5s intervals)..."
      sleep 5
    done

    # ========================================================================
    # 2. Create support router identity on the controller
    # ========================================================================
    echo "==> Creating support router on controller..."

    # Authenticate to the management API
    MGMT_URL="https://127.0.0.1:1280"
    CACERT="$CONTROLLER_DIR/data/pki/cas.pem"

    # Get API session token
    API_TOKEN=$(curl -sk -X POST "$MGMT_URL/edge/management/v1/authenticate?method=password" \
      -H "Content-Type: application/json" \
      -d "{\"username\":\"admin\",\"password\":\"$ADMIN_PASSWORD\"}" | jq -r '.data.token')

    if [ -z "$API_TOKEN" ] || [ "$API_TOKEN" = "null" ]; then
      echo "  ERROR: Failed to authenticate to controller"
      exit 1
    fi

    # Create edge router (host mode — tunneler enabled, no traversal)
    ROUTER_RESP=$(curl -sk -X POST "$MGMT_URL/edge/management/v1/edge-routers" \
      -H "Content-Type: application/json" \
      -H "zt-session: $API_TOKEN" \
      -d '{
        "name": "support-router",
        "roleAttributes": ["support", "public"],
        "isTunnelerEnabled": true
      }')

    ROUTER_ID=$(echo "$ROUTER_RESP" | jq -r '.data.id')
    if [ -z "$ROUTER_ID" ] || [ "$ROUTER_ID" = "null" ]; then
      # Router may already exist
      ROUTER_ID=$(curl -sk "$MGMT_URL/edge/management/v1/edge-routers?filter=name%3D%22support-router%22" \
        -H "zt-session: $API_TOKEN" | jq -r '.data[0].id')
      if [ -z "$ROUTER_ID" ] || [ "$ROUTER_ID" = "null" ]; then
        echo "  ERROR: Failed to create or find support router"
        exit 1
      fi
      echo "  Support router already exists: $ROUTER_ID"
    else
      echo "  Created support router: $ROUTER_ID"
    fi

    # Fetch enrollment JWT for the router
    ENROLLMENT_JWT=$(curl -sk "$MGMT_URL/edge/management/v1/edge-routers/$ROUTER_ID" \
      -H "zt-session: $API_TOKEN" | jq -r '.data.enrollmentJwt // empty')

    if [ -n "$ENROLLMENT_JWT" ]; then
      echo "$ENROLLMENT_JWT" > "$ROUTER_JWT_FILE"
      chmod 600 "$ROUTER_JWT_FILE"
      echo "  Saved enrollment JWT to $ROUTER_JWT_FILE"
    else
      echo "  WARNING: No enrollment JWT available (router may already be enrolled)"
    fi

    # ========================================================================
    # 3. Start Ziti Router
    # ========================================================================
    echo "==> Starting Ziti Router..."

    cat > "$ROUTER_DIR/docker-compose.yml" << ROUTEREOF
services:
  chown-router:
    image: busybox
    command: chown -R 2171 /ziti-router
    volumes:
      - $ROUTER_DIR/data:/ziti-router
  ziti-router:
    image: $ROUTER_IMAGE
    container_name: ziti-router
    depends_on:
      chown-router:
        condition: service_completed_successfully
    user: "2171"
    volumes:
      - $ROUTER_DIR/data:/ziti-router
    environment:
      ZITI_CTRL_ADVERTISED_ADDRESS: ziti.support.example.com
      ZITI_CTRL_ADVERTISED_PORT: "1280"
      ZITI_ENROLL_TOKEN: "$ENROLLMENT_JWT"
      ZITI_ROUTER_ADVERTISED_ADDRESS: ziti.support.example.com
      ZITI_ROUTER_PORT: "3022"
      ZITI_ROUTER_MODE: host
      ZITI_BOOTSTRAP: "true"
      ZITI_BOOTSTRAP_ENROLLMENT: "true"
      ZITI_AUTO_RENEW_CERTS: "true"
    restart: unless-stopped
    network_mode: host
    healthcheck:
      test: ["CMD", "ziti", "agent", "stats"]
      interval: 3s
      timeout: 3s
      retries: 5
      start_period: 15s
ROUTEREOF

    cd "$ROUTER_DIR"
    docker-compose pull
    docker-compose up -d

    echo "  Waiting for router to become healthy..."
    for i in $(seq 1 40); do
      if docker inspect ziti-router --format='{{.State.Health.Status}}' 2>/dev/null | grep -q healthy; then
        echo "  Router is healthy"
        break
      fi
      echo "  Attempt $i/40..."
      sleep 3
    done

    # ========================================================================
    # 4. Store admin password in Vault
    # ========================================================================
    if [ -f "$KEYS_FILE" ]; then
      ROOT_TOKEN=$(jq -r '.root_token' "$KEYS_FILE")
      for VAULT_NS in kss kcs; do
        curl -sf -X POST \
          -H "X-Vault-Token: $ROOT_TOKEN" \
          -H "X-Vault-Namespace: $VAULT_NS" \
          -H "Content-Type: application/json" \
          -d "$(jq -n --arg pass "$ADMIN_PASSWORD" '{data: {password: $pass, username: "admin"}}')" \
          "$VAULT_ADDR/v1/secret/data/ziti/admin"
        echo "  Stored ziti/admin in $VAULT_NS"
      done
    fi

    # Mark setup complete
    touch "$SETUP_MARKER"

    echo ""
    echo "==> OpenZiti installation complete!"
    echo "    Controller: https://ziti.support.example.com:1280"
    echo "    Username: admin"
    echo "    Password: $ADMIN_PASSWORD"
  '';
in
{
  # Ziti auto-setup service — controller + router via Docker Compose
  systemd.services.ziti-setup = {
    description = "OpenZiti Auto-Setup (Controller + Router)";
    requires = [ "docker.service" ];
    after = [ "docker.service" "network-online.target" "openbao-auto-init.service" ];
    wants = [ "openbao-auto-init.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = zitiAutoSetup;
      TimeoutStartSec = "15min";
    };

    unitConfig = {
      StartLimitIntervalSec = 0;
    };
  };

  # Ensure directories exist
  systemd.tmpfiles.rules = [
    "d ${zitiDir} 0755 root root -"
    "d ${controllerDir} 0755 root root -"
    "d ${controllerDir}/data 0755 root root -"
    "d ${routerDir} 0755 root root -"
    "d ${routerDir}/data 0755 root root -"
    "d /etc/ziti 0750 root root -"
  ];

  # Firewall: controller management API + router edge connections
  # Ziti handles its own TLS (like Teleport), not behind nginx
  networking.firewall.allowedTCPPorts = [
    1280  # Controller management + edge API
    3022  # Router edge connections
  ];
}
