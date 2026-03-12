# HashiCorp Vault configuration
# Secrets management with file storage backend
# Auto-initializes and auto-unseals for IaC workflows

{ config, pkgs, lib, ... }:

let
  deployConfig = import ../generated-config.nix;
  # Data and configuration directories
  vaultDataDir = "/var/lib/vault";
  vaultConfigDir = "/etc/vault.d";
  # Use pre-built binary to avoid lengthy compilation
  vaultPkg = pkgs.vault-bin;

  # Auto-init and unseal script
  vaultAutoInit = pkgs.writeShellScript "vault-auto-init" ''
    set -eu

    export PATH="${pkgs.jq}/bin:${vaultPkg}/bin:$PATH"
    export VAULT_ADDR="http://127.0.0.1:8200"
    KEYS_FILE="${vaultDataDir}/init-keys.json"
    PKI_MARKER="${vaultDataDir}/.pki-configured"

    # Wait for Vault to be ready (vault status returns 0=unsealed, 1=error, 2=sealed)
    echo "Waiting for Vault to be ready..."
    for i in $(seq 1 60); do
      STATUS_CODE=$(vault status >/dev/null 2>&1; echo $?)
      if [ "$STATUS_CODE" = "0" ] || [ "$STATUS_CODE" = "2" ]; then
        echo "Vault is responding (status code: $STATUS_CODE)"
        break
      fi
      echo "  Attempt $i/60... (status code: $STATUS_CODE)"
      sleep 2
    done

    # Get vault status JSON to temp file (vault status returns non-zero when sealed)
    VAULT_STATUS_FILE=$(mktemp)
    vault status -format=json > "$VAULT_STATUS_FILE" 2>/dev/null || true

    # Check if initialized (use 'if' to handle false properly - jq's // treats false as falsey)
    INIT_STATUS=$(jq -r 'if .initialized == null then "unknown" else .initialized end' "$VAULT_STATUS_FILE")
    echo "Vault initialized: $INIT_STATUS"

    if [ "$INIT_STATUS" = "false" ]; then
      echo "Initializing Vault..."
      vault operator init \
        -key-shares=1 \
        -key-threshold=1 \
        -format=json > "$KEYS_FILE"
      chmod 600 "$KEYS_FILE"
      chown vault:vault "$KEYS_FILE"
      echo "Vault initialized. Keys stored in $KEYS_FILE"
      # Refresh status after init
      vault status -format=json > "$VAULT_STATUS_FILE" 2>/dev/null || true
    fi

    # Check if sealed
    SEALED=$(jq -r '.sealed // "unknown"' "$VAULT_STATUS_FILE")
    echo "Vault sealed: $SEALED"
    rm -f "$VAULT_STATUS_FILE"

    if [ "$SEALED" = "true" ]; then
      if [ ! -f "$KEYS_FILE" ]; then
        echo "ERROR: Vault is sealed but no keys file found at $KEYS_FILE"
        exit 1
      fi
      echo "Unsealing Vault..."
      UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' "$KEYS_FILE")
      vault operator unseal "$UNSEAL_KEY" >/dev/null
      echo "Vault unsealed"
    fi

    # Configure PKI if not already done
    if [ ! -f "$PKI_MARKER" ]; then
      echo "Configuring PKI..."

      # Get root token
      ROOT_TOKEN=$(jq -r '.root_token' "$KEYS_FILE")
      export VAULT_TOKEN="$ROOT_TOKEN"

      # Enable PKI secrets engine for root CA
      if ! vault secrets list -format=json | jq -e '.["pki/"]' >/dev/null 2>&1; then
        vault secrets enable -path=pki pki
        vault secrets tune -max-lease-ttl=87600h pki

        # Generate root CA
        vault write -field=certificate pki/root/generate/internal \
          common_name="${deployConfig.supportPrefix} Root CA" \
          ttl=87600h > /dev/null

        # Configure URLs
        vault write pki/config/urls \
          issuing_certificates="https://vault.${deployConfig.domain}/v1/pki/ca" \
          crl_distribution_points="https://vault.${deployConfig.domain}/v1/pki/crl"

        echo "Root CA created"
      fi

      # Enable intermediate PKI
      if ! vault secrets list -format=json | jq -e '.["pki_int/"]' >/dev/null 2>&1; then
        vault secrets enable -path=pki_int pki
        vault secrets tune -max-lease-ttl=43800h pki_int

        # Generate and sign intermediate
        vault write -format=json pki_int/intermediate/generate/internal \
          common_name="${deployConfig.supportPrefix} Intermediate CA" \
          | jq -r '.data.csr' > /tmp/intermediate.csr

        vault write -format=json pki/root/sign-intermediate \
          csr=@/tmp/intermediate.csr \
          format=pem_bundle \
          ttl=43800h \
          | jq -r '.data.certificate' > /tmp/intermediate.crt

        vault write pki_int/intermediate/set-signed \
          certificate=@/tmp/intermediate.crt

        rm -f /tmp/intermediate.csr /tmp/intermediate.crt
        echo "Intermediate CA created"
      fi

      # Create certificate issuing role
      if ! vault read pki_int/roles/${deployConfig.supportPrefix} >/dev/null 2>&1; then
        vault write pki_int/roles/${deployConfig.supportPrefix} \
          allowed_domains="${deployConfig.domain},${deployConfig.baseDomain}" \
          allow_subdomains=true \
          allow_bare_domains=true \
          max_ttl=8760h
        echo "Certificate role '${deployConfig.supportPrefix}' created"
      fi

      touch "$PKI_MARKER"
      echo "PKI configuration complete"
    else
      echo "PKI already configured"
    fi

    echo "Vault auto-init complete"
  '';
in
{
  # Install Vault package (pre-built binary)
  environment.systemPackages = [ vaultPkg pkgs.jq ];

  # Create Vault user and group
  users.users.vault = {
    isSystemUser = true;
    group = "vault";
    home = vaultDataDir;
    createHome = true;
    description = "Vault daemon user";
  };
  users.groups.vault = {};

  # Vault systemd service
  systemd.services.vault = {
    description = "HashiCorp Vault - A tool for managing secrets";
    documentation = [ "https://www.vaultproject.io/docs" ];
    requires = [ "network-online.target" ];
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      User = "vault";
      Group = "vault";
      ExecStart = "${vaultPkg}/bin/vault server -config=${vaultConfigDir}/vault.hcl";
      ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
      Restart = "on-failure";
      RestartSec = "5s";

      # Security hardening
      CapabilityBoundingSet = "CAP_IPC_LOCK";
      AmbientCapabilities = "CAP_IPC_LOCK";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ReadWritePaths = [ vaultDataDir vaultConfigDir ];
      LimitNOFILE = 65536;
      LimitMEMLOCK = "infinity";
    };

    # Set environment for Vault CLI
    environment = {
      VAULT_ADDR = "http://127.0.0.1:8200";
    };
  };

  # Vault configuration file
  environment.etc."vault.d/vault.hcl" = {
    mode = "0640";
    user = "vault";
    group = "vault";
    text = ''
      # Vault configuration

      # Listener - bind to localhost only, Nginx handles TLS termination
      listener "tcp" {
        address       = "127.0.0.1:8200"
        tls_disable   = true
      }

      # Also listen on private interface for direct cluster access
      listener "tcp" {
        address       = "0.0.0.0:8201"
        tls_disable   = true
        # In production, enable TLS for cluster port
      }

      # File storage backend - simple and works well for single node
      storage "file" {
        path = "${vaultDataDir}/data"
      }

      # API address for clients
      api_addr = "https://vault.${deployConfig.domain}"

      # Cluster address (for HA, not used with file backend)
      cluster_addr = "https://support.local:8201"

      # UI
      ui = true

      # Logging
      log_level = "info"

      # Disable mlock if needed (can cause issues in containers/VMs)
      disable_mlock = false
    '';
  };

  # Auto-init and unseal service
  systemd.services.vault-auto-init = {
    description = "Vault Auto-Initialize and Unseal";
    after = [ "vault.service" ];
    requires = [ "vault.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = vaultAutoInit;
      User = "root";  # Needs root to write to vault dir initially
    };

    environment = {
      VAULT_ADDR = "http://127.0.0.1:8200";
    };
  };

  # Ensure data directory exists with correct permissions
  systemd.tmpfiles.rules = [
    "d ${vaultDataDir} 0750 vault vault -"
    "d ${vaultDataDir}/data 0750 vault vault -"
    "d ${vaultConfigDir} 0750 vault vault -"
  ];

  # Firewall rules for Vault
  # Port 8200 is proxied via Nginx, 8201 for cluster communication
  networking.firewall.allowedTCPPorts = [
    8201  # Vault cluster port (direct access from k8s nodes)
  ];
}
