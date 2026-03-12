# Teleport — unified access plane for SSH, K8s, web apps
# Runs natively via NixOS services.teleport (auth + proxy + SSH)
# Uses local auth (OIDC/SAML requires Teleport Enterprise)
# Auto-creates admin user on first boot
# Join tokens managed by OpenTofu (tofu/modules/teleport-config)

{ config, pkgs, lib, ... }:

let
  teleportDataDir = "/var/lib/teleport";
  acmeCertDir = "/var/lib/acme/support.example.com";
  certFile = "${acmeCertDir}/fullchain.pem";
  keyFile = "${acmeCertDir}/key.pem";
  setupMarker = "${teleportDataDir}/.setup-complete-v3";

  # Auto-setup: local admin user (join tokens managed by OpenTofu)
  teleportAutoSetup = pkgs.writeShellScript "teleport-auto-setup" ''
    set -eu

    export PATH="${lib.makeBinPath [
      pkgs.teleport pkgs.coreutils pkgs.openssl pkgs.gnugrep
    ]}"

    SETUP_MARKER="${setupMarker}"
    ADMIN_PASSWORD_FILE="/etc/teleport/admin_password"

    if [ -f "$SETUP_MARKER" ]; then
      echo "Teleport auto-setup already complete"
      exit 0
    fi

    # Wait for Teleport to be ready
    echo "Waiting for Teleport to be ready..."
    for i in $(seq 1 60); do
      if tctl status >/dev/null 2>&1; then
        echo "Teleport is ready"
        break
      fi
      if [ "$i" = "60" ]; then
        echo "ERROR: Teleport did not become ready in time"
        exit 1
      fi
      echo "  Attempt $i/60..."
      sleep 5
    done

    # ========================================================================
    # Create local admin user
    # ========================================================================
    echo "Creating local admin user..."

    # Generate admin password
    if [ ! -f "$ADMIN_PASSWORD_FILE" ]; then
      mkdir -p /etc/teleport
      openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 20 > "$ADMIN_PASSWORD_FILE"
      chmod 600 "$ADMIN_PASSWORD_FILE"
    fi

    # Create admin user with all built-in roles
    if ! tctl users ls 2>/dev/null | grep -q "^admin"; then
      tctl users add admin --roles=access,editor --logins=root,vagrant
      echo "  Admin user 'admin' created"
      echo "  NOTE: Complete registration via the link shown above, or reset with:"
      echo "    tctl users reset admin"
    else
      echo "  Admin user 'admin' already exists"
    fi

    # Mark setup complete
    mkdir -p "$(dirname "$SETUP_MARKER")"
    touch "$SETUP_MARKER"
    echo "Teleport auto-setup complete!"
  '';
in
{
  # Teleport service via NixOS module
  services.teleport = {
    enable = true;

    settings = {
      teleport = {
        nodename = "support";
        data_dir = teleportDataDir;
        log.severity = "INFO";
      };

      auth_service = {
        enabled = true;
        cluster_name = "overkill";
        listen_addr = "0.0.0.0:3025";
        authentication = {
          type = "local";
          second_factor = "otp";
        };
      };

      proxy_service = {
        enabled = true;
        web_listen_addr = "0.0.0.0:3080";
        public_addr = "teleport.support.example.com:3080";
        ssh_public_addr = "teleport.support.example.com:3023";
        tunnel_public_addr = "teleport.support.example.com:3024";
        kube_public_addr = "teleport.support.example.com:3026";
        kube_listen_addr = "0.0.0.0:3026";
        https_keypairs = [
          {
            cert_file = certFile;
            key_file = keyFile;
          }
        ];
        acme = { enabled = false; };
      };

      ssh_service = {
        enabled = true;
        labels = {
          role = "support";
          env = "homelab";
        };
      };
    };
  };

  # Ensure Teleport starts after certs are available
  systemd.services.teleport = {
    after = [ "acme-support.example.com.service" "network-online.target" ];
    wants = [ "acme-support.example.com.service" ];
  };

  # Auto-setup: local admin user
  systemd.services.teleport-auto-setup = {
    description = "Teleport Auto-Setup (local admin)";
    after = [ "teleport.service" ];
    requires = [ "teleport.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = teleportAutoSetup;
      User = "root";
      TimeoutStartSec = "5min";
    };
  };

  # Ensure directories exist
  systemd.tmpfiles.rules = [
    "d ${teleportDataDir} 0750 root root -"
    "d /etc/teleport 0750 root root -"
  ];

  # Teleport needs tctl/tsh available
  environment.systemPackages = [ pkgs.teleport ];

  # Firewall: Teleport proxy ports (handles own TLS, not behind nginx)
  networking.firewall.allowedTCPPorts = [
    3080  # Web UI + HTTPS proxy
    3023  # SSH proxy
    3024  # Reverse tunnel
    3026  # Kubernetes proxy
  ];
}
