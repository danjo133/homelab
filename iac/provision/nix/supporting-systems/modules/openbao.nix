# OpenBao configuration (Apache 2.0 fork of Vault)
# Secrets management with file storage backend and per-cluster namespaces
# Auto-initializes, auto-unseals, and configures namespaces for IaC workflows

{ config, pkgs, lib, ... }:

let
  # Data directory (managed by systemd StateDirectory via the NixOS module)
  openbaoDataDir = "/var/lib/openbao";

  # Auto-init, unseal, and configure namespaces
  openbaoAutoInit = pkgs.writeShellScript "openbao-auto-init" ''
    set -eu

    export PATH="${pkgs.jq}/bin:${pkgs.openbao}/bin:$PATH"
    export BAO_ADDR="http://127.0.0.1:8200"
    KEYS_FILE="${openbaoDataDir}/init-keys.json"
    PKI_MARKER="${openbaoDataDir}/.pki-configured"
    NS_MARKER="${openbaoDataDir}/.namespaces-configured"

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

    # Get root token for configuration
    ROOT_TOKEN=$(jq -r '.root_token' "$KEYS_FILE")
    export BAO_TOKEN="$ROOT_TOKEN"

    # Configure root PKI if not already done
    if [ ! -f "$PKI_MARKER" ]; then
      echo "Configuring root PKI..."

      # Enable PKI secrets engine for root CA
      if ! bao secrets list -format=json | jq -e '.["pki/"]' >/dev/null 2>&1; then
        bao secrets enable -path=pki pki
        bao secrets tune -max-lease-ttl=87600h pki

        # Generate root CA
        bao write -field=certificate pki/root/generate/internal \
          common_name="Overkill Root CA" \
          ttl=87600h > /dev/null

        # Configure URLs
        bao write pki/config/urls \
          issuing_certificates="https://vault.support.example.com/v1/pki/ca" \
          crl_distribution_points="https://vault.support.example.com/v1/pki/crl"

        echo "Root CA created"
      fi

      touch "$PKI_MARKER"
      echo "Root PKI configuration complete"
    else
      echo "Root PKI already configured"
    fi

    # Configure per-cluster namespaces
    if [ ! -f "$NS_MARKER" ]; then
      echo "Configuring per-cluster namespaces..."

      for NS in kss kcs; do
        echo "--- Namespace: $NS ---"

        # Create namespace
        if bao namespace list -format=json 2>/dev/null | jq -e ".\"$NS/\"" >/dev/null 2>&1; then
          echo "  Namespace '$NS' already exists"
        else
          bao namespace create "$NS"
          echo "  Namespace '$NS' created"
        fi

        # Work within this namespace
        export BAO_NAMESPACE="$NS"

        # Enable KV v2 secrets engine
        if ! bao secrets list -format=json | jq -e '.["secret/"]' >/dev/null 2>&1; then
          bao secrets enable -path=secret -version=2 kv
          echo "  KV v2 enabled in $NS"
        else
          echo "  KV v2 already enabled in $NS"
        fi

        # Create external-secrets policy
        bao policy write external-secrets - <<POLICY
# Policy for external-secrets operator
path "secret/data/*" {
  capabilities = ["read"]
}
path "secret/metadata/*" {
  capabilities = ["read", "list"]
}
POLICY
        echo "  external-secrets policy created in $NS"

        # Create spiffe-workload policy
        bao policy write spiffe-workload - <<POLICY
# Allow SPIFFE workloads to read secrets scoped to their namespace
path "secret/data/workloads/*" {
  capabilities = ["read"]
}
# Allow PKI certificate issuance
path "pki_int/issue/overkill" {
  capabilities = ["create", "update"]
}
POLICY
        echo "  spiffe-workload policy created in $NS"

        # Enable intermediate PKI
        if ! bao secrets list -format=json | jq -e '.["pki_int/"]' >/dev/null 2>&1; then
          bao secrets enable -path=pki_int pki
          bao secrets tune -max-lease-ttl=43800h pki_int

          # Generate intermediate CSR
          bao write -format=json pki_int/intermediate/generate/internal \
            common_name="Overkill Intermediate CA ($NS)" \
            | jq -r '.data.csr' > /tmp/intermediate-$NS.csr

          # Sign with root CA (must switch back to root namespace)
          unset BAO_NAMESPACE
          bao write -format=json pki/root/sign-intermediate \
            csr=@/tmp/intermediate-$NS.csr \
            format=pem_bundle \
            ttl=43800h \
            | jq -r '.data.certificate' > /tmp/intermediate-$NS.crt
          export BAO_NAMESPACE="$NS"

          # Set the signed certificate
          bao write pki_int/intermediate/set-signed \
            certificate=@/tmp/intermediate-$NS.crt

          rm -f /tmp/intermediate-$NS.csr /tmp/intermediate-$NS.crt
          echo "  Intermediate CA created for $NS"
        else
          echo "  Intermediate CA already exists in $NS"
        fi

        # Create certificate issuing role
        if ! bao read pki_int/roles/overkill >/dev/null 2>&1; then
          bao write pki_int/roles/overkill \
            allowed_domains="support.example.com,example.com" \
            allow_subdomains=true \
            allow_bare_domains=true \
            max_ttl=8760h
          echo "  Certificate role 'overkill' created in $NS"
        fi

        # Clear namespace for next iteration
        unset BAO_NAMESPACE
      done

      touch "$NS_MARKER"
      echo "Namespace configuration complete"
    else
      echo "Namespaces already configured"
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
    description = "OpenBao Auto-Initialize, Unseal, and Configure Namespaces";
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
