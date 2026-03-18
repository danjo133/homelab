# Vault/OpenBao CA trust configuration
# Fetches root CA certificate and adds it to system trust store
# This allows k8s nodes to trust certificates issued by the PKI
# Root CA is in the root namespace; per-cluster intermediate CAs are in namespaces

{ config, pkgs, lib, ... }:

let
  # Vault URL for fetching CA - from cluster options
  vaultAddr = config.kss.cluster.vaultAddr;

  # Script to fetch and install Vault CA
  fetchVaultCA = pkgs.writeShellScript "fetch-vault-ca" ''
    set -eu

    export PATH="${lib.makeBinPath [ pkgs.curl pkgs.openssl pkgs.coreutils ]}"

    CA_FILE="/etc/ssl/certs/vault-ca.pem"
    VAULT_URL="${vaultAddr}/v1/pki/ca/pem"

    echo "Fetching Vault CA from $VAULT_URL..."

    # Try to fetch CA certificate (with retry for boot timing)
    for i in $(seq 1 30); do
      if curl -sf -o "$CA_FILE.tmp" "$VAULT_URL" 2>/dev/null; then
        # Verify it's a valid certificate
        if openssl x509 -in "$CA_FILE.tmp" -noout 2>/dev/null; then
          mv "$CA_FILE.tmp" "$CA_FILE"
          chmod 644 "$CA_FILE"
          echo "Vault CA certificate installed to $CA_FILE"

          # Update CA certificates bundle
          if command -v update-ca-certificates >/dev/null 2>&1; then
            update-ca-certificates
          fi
          exit 0
        else
          echo "  Invalid certificate received, retrying..."
          rm -f "$CA_FILE.tmp"
        fi
      fi
      echo "  Attempt $i/30 failed, retrying in 5s..."
      sleep 5
    done

    echo "WARNING: Failed to fetch Vault CA after 30 attempts"
    echo "The certificate may need to be installed manually"
    exit 0  # Don't fail boot if Vault is unavailable
  '';
in
{
  # Systemd service to fetch Vault CA on boot
  systemd.services.vault-ca-fetch = {
    description = "Fetch Vault CA Certificate";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = fetchVaultCA;
    };
  };

  # Timer to periodically refresh CA (in case it's renewed)
  systemd.timers.vault-ca-refresh = {
    description = "Periodic Vault CA refresh";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1h";
      OnUnitActiveSec = "24h";
      Unit = "vault-ca-fetch.service";
    };
  };

  # SSL configuration
  security.pki.certificateFiles = [];  # We manage CA manually

  # Also add support VM hosts entry for bootstrap
  # (before DNS is configured, nodes can use IP)
  networking.extraHosts = ''
    # Support VM services - use mDNS or configure DNS
    # 10.69.50.x vault.support.example.com harbor.example.com
  '';
}
