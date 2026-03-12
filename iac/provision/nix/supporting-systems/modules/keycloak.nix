# Keycloak Identity Provider (Root IdP)
# Runs on the support VM as the "upstream" corporate IdP
# Uses NixOS services.keycloak with PostgreSQL backend
# Realm, users, clients, and Vault secrets are managed by OpenTofu

{ config, pkgs, lib, ... }:

let
  deployConfig = import ../generated-config.nix;
  keycloakPort = 8180;
  keycloakMgmtPort = 9990;
  keycloakAdminUser = "admin";
  keycloakAdminPassFile = config.sops.secrets.keycloak_admin_password.path;

  # Deliver OIDC client secrets to local files for Teleport and GitLab
  # These services read their client secrets from disk at setup time.
  # The clients themselves are managed by OpenTofu (keycloak-upstream module).
  keycloakOidcSecretDelivery = pkgs.writeShellScript "keycloak-oidc-secret-delivery" ''
    set -eu

    export PATH="${lib.makeBinPath [
      pkgs.curl pkgs.jq pkgs.coreutils pkgs.gnugrep
    ]}"

    KEYCLOAK_URL="http://127.0.0.1:${toString keycloakPort}"
    ADMIN_USER="${keycloakAdminUser}"
    ADMIN_PASS_FILE="${keycloakAdminPassFile}"

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
    TOKEN=$(curl -sf -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "username=$ADMIN_USER" \
      -d "password=$ADMIN_PASS" \
      -d "grant_type=password" \
      -d "client_id=admin-cli" \
      | jq -r '.access_token')

    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
      echo "ERROR: Failed to get admin access token"
      exit 1
    fi

    # Fetch and write client secret to file
    deliver_secret() {
      local CLIENT_ID="$1"
      local DEST="$2"

      local UUID
      UUID=$(curl -sf \
        -H "Authorization: Bearer $TOKEN" \
        "$KEYCLOAK_URL/admin/realms/upstream/clients?clientId=$CLIENT_ID" \
        | jq -r '.[0].id // empty')

      if [ -z "$UUID" ]; then
        echo "WARNING: Client '$CLIENT_ID' not found in upstream realm"
        return 0
      fi

      local SECRET
      SECRET=$(curl -sf \
        -H "Authorization: Bearer $TOKEN" \
        "$KEYCLOAK_URL/admin/realms/upstream/clients/$UUID/client-secret" \
        | jq -r '.value // empty')

      if [ -z "$SECRET" ]; then
        echo "WARNING: Could not retrieve secret for client '$CLIENT_ID'"
        return 0
      fi

      mkdir -p "$(dirname "$DEST")"
      echo -n "$SECRET" > "$DEST"
      chmod 600 "$DEST"
      echo "Delivered $CLIENT_ID secret to $DEST"
    }

    deliver_secret "teleport" "/etc/teleport/oidc-client-secret"
    deliver_secret "gitlab" "/etc/gitlab/oidc-client-secret"

    echo "OIDC secret delivery complete"
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
      hostname = "idp.${deployConfig.domain}";
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

  # Deliver OIDC client secrets to local files for Teleport and GitLab
  # Realm, users, clients, and Vault secrets are managed by OpenTofu
  systemd.services.keycloak-oidc-secrets = {
    description = "Deliver Keycloak OIDC client secrets to local files";
    after = [ "keycloak.service" ];
    requires = [ "keycloak.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = keycloakOidcSecretDelivery;
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
