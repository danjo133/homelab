# Keycloak Identity Provider (Root IdP)
# Runs on the support VM as the "upstream" corporate IdP
# Uses NixOS services.keycloak with PostgreSQL backend
# Auto-configures upstream realm, test users, and broker-client for federation

{ config, pkgs, lib, ... }:

let
  keycloakPort = 8180;
  keycloakMgmtPort = 9990;
  keycloakAdminUser = "admin";
  keycloakAdminPassFile = config.sops.secrets.keycloak_admin_password.path;
  vaultAddr = "http://127.0.0.1:8200";
  keysFile = "/var/lib/vault/init-keys.json";
  setupMarker = "/var/lib/keycloak/.setup-complete";

  # Auto-setup script: creates upstream realm, test users, broker-client
  keycloakAutoSetup = pkgs.writeShellScript "keycloak-auto-setup" ''
    set -eu

    export PATH="${lib.makeBinPath [
      pkgs.curl pkgs.jq pkgs.coreutils pkgs.openssl pkgs.gnugrep
    ]}"

    KEYCLOAK_URL="http://127.0.0.1:${toString keycloakPort}"
    ADMIN_USER="${keycloakAdminUser}"
    ADMIN_PASS_FILE="${keycloakAdminPassFile}"
    VAULT_ADDR="${vaultAddr}"
    KEYS_FILE="${keysFile}"
    SETUP_MARKER="${setupMarker}"

    if [ -f "$SETUP_MARKER" ]; then
      echo "Keycloak auto-setup already complete"
      exit 0
    fi

    # Wait for Keycloak to be ready
    echo "Waiting for Keycloak to be ready..."
    for i in $(seq 1 90); do
      if curl -sf "http://127.0.0.1:${toString keycloakMgmtPort}/health/ready" >/dev/null 2>&1; then
        echo "Keycloak is ready"
        break
      fi
      if [ "$i" = "90" ]; then
        echo "ERROR: Keycloak did not become ready in time"
        exit 1
      fi
      echo "  Attempt $i/90..."
      sleep 5
    done

    # Read admin password
    if [ ! -f "$ADMIN_PASS_FILE" ]; then
      echo "ERROR: Admin password file not found at $ADMIN_PASS_FILE"
      exit 1
    fi
    ADMIN_PASS=$(cat "$ADMIN_PASS_FILE")

    # Get admin access token
    get_token() {
      curl -sf -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=$ADMIN_USER" \
        -d "password=$ADMIN_PASS" \
        -d "grant_type=password" \
        -d "client_id=admin-cli" \
        | jq -r '.access_token'
    }

    TOKEN=$(get_token)
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
      echo "ERROR: Failed to get admin access token"
      exit 1
    fi

    # Helper: authenticated API call
    kc_api() {
      local METHOD="$1"
      local ENDPOINT="$2"
      shift 2
      curl -sf -X "$METHOD" \
        "$KEYCLOAK_URL/admin/realms$ENDPOINT" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        "$@"
    }

    # Helper: check if resource exists (returns 0 if exists)
    kc_exists() {
      local ENDPOINT="$1"
      curl -sf -o /dev/null -w "%{http_code}" \
        "$KEYCLOAK_URL/admin/realms$ENDPOINT" \
        -H "Authorization: Bearer $TOKEN" | grep -q "200"
    }

    # ========================================================================
    # 1. Create 'upstream' realm
    # ========================================================================
    echo "Creating upstream realm..."
    if kc_exists "/upstream"; then
      echo "  Realm 'upstream' already exists"
    else
      kc_api POST "" -d '{
        "realm": "upstream",
        "enabled": true,
        "displayName": "Upstream Corporate IdP",
        "registrationAllowed": false,
        "loginWithEmailAllowed": true,
        "duplicateEmailsAllowed": false,
        "resetPasswordAllowed": true,
        "editUsernameAllowed": false,
        "bruteForceProtected": true,
        "accessTokenLifespan": 300,
        "ssoSessionIdleTimeout": 1800,
        "ssoSessionMaxLifespan": 36000
      }' || echo "  Realm may already exist"
      echo "  Realm 'upstream' created"
    fi

    # Refresh token (realm creation may have invalidated it)
    TOKEN=$(get_token)

    # ========================================================================
    # 2. Create realm roles
    # ========================================================================
    echo "Creating realm roles..."
    for ROLE in admin user; do
      if kc_api GET "/upstream/roles/$ROLE" >/dev/null 2>&1; then
        echo "  Role '$ROLE' already exists"
      else
        kc_api POST "/upstream/roles" -d "{
          \"name\": \"$ROLE\",
          \"description\": \"$ROLE role\"
        }" || echo "  Role '$ROLE' may already exist"
        echo "  Role '$ROLE' created"
      fi
    done

    # ========================================================================
    # 3. Create test users: alice (admin), bob (developer), carol (viewer)
    # ========================================================================
    echo "Creating test users..."

    generate_password() {
      openssl rand -base64 16 | tr -d '=/+' | head -c 20
    }

    ALICE_PASS=$(generate_password)
    BOB_PASS=$(generate_password)
    CAROL_PASS=$(generate_password)
    DAVE_PASS=$(generate_password)

    create_user() {
      local USERNAME="$1"
      local EMAIL="$2"
      local FIRSTNAME="$3"
      local LASTNAME="$4"
      local PASSWORD="$5"
      local ROLE="$6"

      # Check if user exists
      EXISTING=$(kc_api GET "/upstream/users?username=$USERNAME&exact=true" 2>/dev/null || echo "[]")
      if echo "$EXISTING" | jq -e '.[0].id' >/dev/null 2>&1; then
        echo "  User '$USERNAME' already exists"
        return 0
      fi

      # Create user
      kc_api POST "/upstream/users" -d "{
        \"username\": \"$USERNAME\",
        \"email\": \"$EMAIL\",
        \"firstName\": \"$FIRSTNAME\",
        \"lastName\": \"$LASTNAME\",
        \"enabled\": true,
        \"emailVerified\": true,
        \"credentials\": [{
          \"type\": \"password\",
          \"value\": \"$PASSWORD\",
          \"temporary\": false
        }]
      }"
      echo "  User '$USERNAME' created"

      # Get user ID
      USER_ID=$(kc_api GET "/upstream/users?username=$USERNAME&exact=true" | jq -r '.[0].id')

      # Assign role
      ROLE_JSON=$(kc_api GET "/upstream/roles/$ROLE")
      kc_api POST "/upstream/users/$USER_ID/role-mappings/realm" -d "[$ROLE_JSON]"
      echo "  Role '$ROLE' assigned to '$USERNAME'"
    }

    create_user "alice" "alice@example.com" "Alice" "Admin" "$ALICE_PASS" "admin"
    create_user "bob" "bob@example.com" "Bob" "Builder" "$BOB_PASS" "user"
    create_user "carol" "carol@example.com" "Carol" "Checker" "$CAROL_PASS" "user"
    create_user "admin" "admin@example.com" "Admin" "User" "$DAVE_PASS" "admin"

    # ========================================================================
    # 4. Create OIDC client 'broker-client' for federation
    # ========================================================================
    echo "Creating broker-client OIDC client..."

    EXISTING_CLIENT=$(kc_api GET "/upstream/clients?clientId=broker-client" 2>/dev/null || echo "[]")
    if echo "$EXISTING_CLIENT" | jq -e '.[0].id' >/dev/null 2>&1; then
      echo "  Client 'broker-client' already exists"
      CLIENT_ID=$(echo "$EXISTING_CLIENT" | jq -r '.[0].id')
    else
      BROKER_SECRET=$(openssl rand -hex 32)

      kc_api POST "/upstream/clients" -d "{
        \"clientId\": \"broker-client\",
        \"name\": \"Broker IdP Federation Client\",
        \"enabled\": true,
        \"protocol\": \"openid-connect\",
        \"publicClient\": false,
        \"secret\": \"$BROKER_SECRET\",
        \"standardFlowEnabled\": true,
        \"directAccessGrantsEnabled\": false,
        \"serviceAccountsEnabled\": false,
        \"authorizationServicesEnabled\": false,
        \"redirectUris\": [
          \"https://auth.simple-k8s.example.com/realms/broker/broker/upstream/endpoint\",
          \"https://auth.*.example.com/realms/broker/broker/upstream/endpoint\"
        ],
        \"webOrigins\": [\"+\"],
        \"defaultClientScopes\": [\"openid\", \"profile\", \"email\", \"roles\"],
        \"attributes\": {
          \"access.token.lifespan\": \"300\"
        }
      }"
      echo "  Client 'broker-client' created"

      CLIENT_ID=$(kc_api GET "/upstream/clients?clientId=broker-client" | jq -r '.[0].id')
    fi

    # Get the client secret (may have been auto-generated or set by us)
    CLIENT_SECRET=$(kc_api GET "/upstream/clients/$CLIENT_ID/client-secret" | jq -r '.value')
    echo "  Broker client secret retrieved"

    # ========================================================================
    # 5. Add 'roles' client scope to include realm roles in tokens
    # ========================================================================
    echo "Configuring roles in tokens..."

    # Check if a 'realm-roles' protocol mapper exists on the roles scope
    ROLES_SCOPE_ID=$(kc_api GET "/upstream/client-scopes" | jq -r '.[] | select(.name=="roles") | .id')
    if [ -n "$ROLES_SCOPE_ID" ] && [ "$ROLES_SCOPE_ID" != "null" ]; then
      echo "  Built-in 'roles' scope found, checking mappers..."
    fi

    # ========================================================================
    # 6. Pre-generate broker realm client secrets
    # ========================================================================
    # These are stored in Vault and injected into the broker Keycloak pod
    # as env vars, then referenced via ''${VAR} substitution in the realm import.
    echo "Generating broker realm client secrets..."
    ARGOCD_CLIENT_SECRET=$(openssl rand -hex 32)
    OAUTH2_PROXY_CLIENT_SECRET=$(openssl rand -hex 32)
    GRAFANA_CLIENT_SECRET=$(openssl rand -hex 32)
    JIT_CLIENT_SECRET=$(openssl rand -hex 32)

    # ========================================================================
    # 7. Store secrets in Vault
    # ========================================================================
    echo "Storing secrets in Vault..."

    if [ ! -f "$KEYS_FILE" ]; then
      echo "WARNING: Vault keys file not found, skipping Vault secret storage"
    else
      ROOT_TOKEN=$(jq -r '.root_token' "$KEYS_FILE")
      export VAULT_TOKEN="$ROOT_TOKEN"

      # Ensure KV v2 is enabled
      if ! curl -sf -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/secret/config" >/dev/null 2>&1; then
        curl -sf -X POST \
          -H "X-Vault-Token: $VAULT_TOKEN" \
          -d '{"type":"kv","options":{"version":"2"}}' \
          "$VAULT_ADDR/v1/sys/mounts/secret" 2>/dev/null || true
      fi

      # Store admin password
      curl -sf -X POST \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg pass "$ADMIN_PASS" '{data: {password: $pass}}')" \
        "$VAULT_ADDR/v1/secret/data/keycloak/admin"
      echo "  Stored keycloak/admin in Vault"

      # Store broker-client secret
      curl -sf -X POST \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg secret "$CLIENT_SECRET" '{data: {"client-secret": $secret}}')" \
        "$VAULT_ADDR/v1/secret/data/keycloak/broker-client"
      echo "  Stored keycloak/broker-client in Vault"

      # Store test user passwords
      curl -sf -X POST \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
          --arg alice "$ALICE_PASS" \
          --arg bob "$BOB_PASS" \
          --arg carol "$CAROL_PASS" \
          --arg admin "$DAVE_PASS" \
          '{data: {"alice-password": $alice, "bob-password": $bob, "carol-password": $carol, "admin-password": $admin}}')" \
        "$VAULT_ADDR/v1/secret/data/keycloak/test-users"
      echo "  Stored keycloak/test-users in Vault"

      # Store broker realm client secrets (pre-generated, pinned via realm import)
      curl -sf -X POST \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg secret "$ARGOCD_CLIENT_SECRET" '{data: {"client-secret": $secret}}')" \
        "$VAULT_ADDR/v1/secret/data/keycloak/argocd-client"
      echo "  Stored keycloak/argocd-client in Vault"

      curl -sf -X POST \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg id "oauth2-proxy" --arg secret "$OAUTH2_PROXY_CLIENT_SECRET" '{data: {"client-id": $id, "client-secret": $secret}}')" \
        "$VAULT_ADDR/v1/secret/data/keycloak/oauth2-proxy-client"
      echo "  Stored keycloak/oauth2-proxy-client in Vault"

      curl -sf -X POST \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg secret "$GRAFANA_CLIENT_SECRET" '{data: {"client-secret": $secret}}')" \
        "$VAULT_ADDR/v1/secret/data/keycloak/grafana-client"
      echo "  Stored keycloak/grafana-client in Vault"

      curl -sf -X POST \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg secret "$JIT_CLIENT_SECRET" '{data: {"client-secret": $secret}}')" \
        "$VAULT_ADDR/v1/secret/data/keycloak/jit-service"
      echo "  Stored keycloak/jit-service in Vault"
    fi

    # Mark setup complete
    mkdir -p "$(dirname "$SETUP_MARKER")"
    touch "$SETUP_MARKER"
    echo "Keycloak auto-setup complete!"
  '';
in
{
  # Keycloak service via NixOS module
  services.keycloak = {
    enable = true;

    database = {
      type = "postgresql";
      createLocally = true;
      username = "keycloak";
      passwordFile = "/etc/keycloak/db_password";
    };

    settings = {
      hostname = "idp.support.example.com";
      http-enabled = true;
      http-host = "127.0.0.1";
      http-port = keycloakPort;
      proxy-headers = "xforwarded";
      # Health endpoint for readiness checks
      health-enabled = true;
      metrics-enabled = true;
      # Default management port 9000 conflicts with MinIO
      http-management-port = 9990;
    };

    # Admin password is injected from sops via keycloak-admin-env service
    # (initialAdminPassword only accepts strings, not file paths)
  };

  # Generate admin password and DB password before Keycloak starts
  systemd.services.keycloak-credentials = {
    description = "Generate Keycloak credentials";
    before = [ "keycloak.service" "postgresql.service" ];
    wantedBy = [ "keycloak.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      export PATH="${lib.makeBinPath [ pkgs.openssl pkgs.coreutils ]}"

      mkdir -p /etc/keycloak
      chmod 750 /etc/keycloak

      # Generate DB password if not exists
      if [ ! -f /etc/keycloak/db_password ]; then
        openssl rand -base64 24 | tr -d '=/+' | head -c 32 > /etc/keycloak/db_password
        chmod 640 /etc/keycloak/db_password
        echo "Generated Keycloak DB password"
      fi
    '';
  };

  # Inject admin password from sops into keycloak's environment
  # (services.keycloak.initialAdminPassword is string-only, can't reference a file)
  systemd.services.keycloak-admin-env = {
    description = "Prepare Keycloak admin credentials from sops";
    before = [ "keycloak.service" ];
    wantedBy = [ "keycloak.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      set -eu
      export PATH="${lib.makeBinPath [ pkgs.coreutils ]}"
      PASS="$(cat ${keycloakAdminPassFile})"
      if [ -z "$PASS" ]; then
        echo "ERROR: Keycloak admin password is empty"
        exit 1
      fi
      mkdir -p /run/keycloak-env
      printf 'KC_BOOTSTRAP_ADMIN_USERNAME=admin\nKC_BOOTSTRAP_ADMIN_PASSWORD=%s\n' \
        "$PASS" > /run/keycloak-env/admin
      chmod 640 /run/keycloak-env/admin
    '';
  };

  # Load the sops-derived admin credentials into keycloak service
  systemd.services.keycloak.serviceConfig.EnvironmentFile =
    [ "/run/keycloak-env/admin" ];

  # Auto-setup service: realm, users, clients, Vault secrets
  systemd.services.keycloak-auto-setup = {
    description = "Keycloak Auto-Setup (upstream realm, users, broker-client)";
    after = [ "keycloak.service" "vault-auto-init.service" ];
    requires = [ "keycloak.service" ];
    wants = [ "vault-auto-init.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = keycloakAutoSetup;
      User = "root";
      # Give Keycloak time to fully start
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 10";
    };
  };

  # Ensure Keycloak data directory exists
  systemd.tmpfiles.rules = [
    "d /var/lib/keycloak 0750 keycloak keycloak -"
  ];

  # Open port for Keycloak (only needed if direct access is desired; nginx proxies)
  # Port 8180 is only on localhost, so no firewall rule needed
}
