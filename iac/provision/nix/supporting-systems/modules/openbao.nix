# OpenBao configuration (Apache 2.0 fork of Vault)
# Secrets management with file storage backend and per-cluster namespaces
# Auto-initializes and auto-unseals on boot
# PKI, namespaces, policies, and secrets are managed by OpenTofu

{ config, pkgs, lib, ... }:

let
  # Data directory (managed by systemd StateDirectory via the NixOS module)
  openbaoDataDir = "/var/lib/openbao";

  # Auto-init and unseal (PKI + namespaces are managed by OpenTofu)
  openbaoAutoInit = pkgs.writeShellScript "openbao-auto-init" ''
    set -eu

    export PATH="${pkgs.jq}/bin:${pkgs.openbao}/bin:$PATH"
    export BAO_ADDR="http://127.0.0.1:8200"
    KEYS_FILE="${openbaoDataDir}/init-keys.json"

    # Wait for OpenBao to be ready (bao status returns 0=unsealed, 1=error, 2=sealed)
    echo "Waiting for OpenBao to be ready..."
    for i in $(seq 1 60); do
      STATUS_CODE=$(bao status >/dev/null 2>&1; echo $?)
      if [ "$STATUS_CODE" = "0" ] || [ "$STATUS_CODE" = "2" ]; then
        echo "OpenBao is responding (status code: $STATUS_CODE)"
        break
      fi
      echo "  Attempt $i/60... (status code: $STATUS_CODE)"
      sleep 2
    done

    # Get status JSON (bao status returns non-zero when sealed)
    BAO_STATUS_FILE=$(mktemp)
    bao status -format=json > "$BAO_STATUS_FILE" 2>/dev/null || true

    # Check if initialized
    INIT_STATUS=$(jq -r 'if .initialized == null then "unknown" else .initialized end' "$BAO_STATUS_FILE")
    echo "OpenBao initialized: $INIT_STATUS"

    if [ "$INIT_STATUS" = "false" ]; then
      echo "Initializing OpenBao..."
      bao operator init \
        -key-shares=1 \
        -key-threshold=1 \
        -format=json > "$KEYS_FILE"
      chmod 600 "$KEYS_FILE"
      echo "OpenBao initialized. Keys stored in $KEYS_FILE"
      # Refresh status after init
      bao status -format=json > "$BAO_STATUS_FILE" 2>/dev/null || true
    fi

    # Check if sealed
    SEALED=$(jq -r '.sealed // "unknown"' "$BAO_STATUS_FILE")
    echo "OpenBao sealed: $SEALED"
    rm -f "$BAO_STATUS_FILE"

    if [ "$SEALED" = "true" ]; then
      if [ ! -f "$KEYS_FILE" ]; then
        echo "ERROR: OpenBao is sealed but no keys file found at $KEYS_FILE"
        exit 1
      fi
      echo "Unsealing OpenBao..."
      UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' "$KEYS_FILE")
      bao operator unseal "$UNSEAL_KEY" >/dev/null
      echo "OpenBao unsealed"
    fi

    echo "OpenBao auto-init complete"
  '';
in
{
  # Install OpenBao package
  environment.systemPackages = [ pkgs.openbao pkgs.jq ];

  # OpenBao service via NixOS module
  services.openbao = {
    enable = true;

    settings = {
      # Named listeners — each key is an arbitrary name, type specifies protocol
      listener = {
        api = {
          type = "tcp";
          address = "127.0.0.1:8200";
          tls_disable = true;
        };
        cluster = {
          type = "tcp";
          address = "0.0.0.0:8201";
          tls_disable = true;
        };
      };

      # File storage backend - simple and works well for single node
      storage.file.path = "${openbaoDataDir}/data";

      # API address for clients
      api_addr = "https://vault.support.example.com";

      # Cluster address
      cluster_addr = "https://support.local:8201";

      # UI
      ui = true;

      # Logging
      log_level = "info";
    };
  };

  # Auto-init and unseal service
  systemd.services.openbao-auto-init = {
    description = "OpenBao Auto-Initialize and Unseal";
    after = [ "openbao.service" ];
    requires = [ "openbao.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = openbaoAutoInit;
      User = "root";  # Needs root to write to openbao dir initially
    };

    environment = {
      BAO_ADDR = "http://127.0.0.1:8200";
    };
  };

  # Firewall rules for OpenBao
  # Port 8200 is proxied via Nginx, 8201 for direct cluster access
  networking.firewall.allowedTCPPorts = [
    8201  # OpenBao cluster port (direct access from k8s nodes)
  ];
}
