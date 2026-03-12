# RKE2 Server (Control Plane) configuration
# Auto-installs RKE2 on first boot and starts the server

{ config, pkgs, lib, ... }:

let
  # RKE2 version
  rke2Version = "v1.31.4+rke2r1";

  # RKE2 installation script
  rke2Install = pkgs.writeShellScript "rke2-server-install" ''
    set -eu

    export PATH="${lib.makeBinPath [ pkgs.curl pkgs.gnutar pkgs.gzip pkgs.coreutils pkgs.bash ]}"

    RKE2_BIN="/var/lib/rancher/rke2/bin"
    MARKER="/var/lib/rancher/rke2/.installed"

    if [ -f "$MARKER" ]; then
      echo "RKE2 already installed"
      exit 0
    fi

    echo "Installing RKE2 server ${rke2Version}..."

    # Create directories
    mkdir -p /var/lib/rancher/rke2/bin
    mkdir -p /etc/rancher/rke2
    mkdir -p /var/log/kubernetes

    # Download RKE2 installer
    curl -sfL https://get.rke2.io -o /tmp/rke2-install.sh
    chmod +x /tmp/rke2-install.sh

    # Install RKE2 server
    INSTALL_RKE2_VERSION="${rke2Version}" \
    INSTALL_RKE2_TYPE="server" \
      bash /tmp/rke2-install.sh

    rm -f /tmp/rke2-install.sh

    # Mark installation complete
    touch "$MARKER"
    echo "RKE2 server installation complete"
  '';

  # Script to store token in Vault (for workers to retrieve)
  storeTokenInVault = pkgs.writeShellScript "store-rke2-token" ''
    set -eu

    export PATH="${lib.makeBinPath [ pkgs.curl pkgs.jq ]}"

    TOKEN_FILE="/var/lib/rancher/rke2/server/node-token"
    VAULT_ADDR="https://vault.support.example.com"

    # Wait for token file
    for i in $(seq 1 60); do
      if [ -f "$TOKEN_FILE" ]; then
        echo "Node token file exists"
        break
      fi
      echo "Waiting for node token... $i/60"
      sleep 5
    done

    if [ ! -f "$TOKEN_FILE" ]; then
      echo "ERROR: Node token not found after 5 minutes"
      exit 1
    fi

    TOKEN=$(cat "$TOKEN_FILE")

    echo "RKE2 node token available at $TOKEN_FILE"
    echo "Workers can join using: server: https://k8s-master:9345"

    # Note: To store in Vault, you would need to authenticate first
    # For now, workers will fetch the token via SSH or shared file
    # TODO: Implement Vault KV storage when auth is configured
  '';
in
{
  # RKE2 server configuration file
  environment.etc."rancher/rke2/config.yaml" = {
    mode = "0644";
    text = ''
      # RKE2 Server Configuration
      # CNI disabled - Cilium will be installed via Helm
      cni: none

      # Disable default components we'll replace
      disable:
        - rke2-canal
        - rke2-ingress-nginx

      # TLS SANs for API server certificate
      tls-san:
        - k8s-master
        - k8s-master.local
        - k8s-master.support.example.com
        - localhost
        - 127.0.0.1

      # Make kubeconfig readable for debugging
      write-kubeconfig-mode: "0644"

      # Audit logging
      kube-apiserver-arg:
        - "audit-log-path=/var/log/kubernetes/audit.log"
        - "audit-log-maxage=30"
        - "audit-log-maxbackup=10"
        - "audit-log-maxsize=100"

      # etcd settings
      etcd-expose-metrics: true
    '';
  };

  # RKE2 installation service
  systemd.services.rke2-server-install = {
    description = "RKE2 Server Installation";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    before = [ "rke2-server.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = rke2Install;
    };
  };

  # RKE2 server service
  systemd.services.rke2-server = {
    description = "RKE2 Kubernetes Server";
    documentation = [ "https://docs.rke2.io" ];
    after = [ "network-online.target" "rke2-server-install.service" ];
    wants = [ "network-online.target" ];
    requires = [ "rke2-server-install.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "notify";
      ExecStart = "/usr/local/bin/rke2 server";
      KillMode = "process";
      Delegate = "yes";
      LimitNOFILE = 1048576;
      LimitNPROC = "infinity";
      LimitCORE = "infinity";
      TasksMax = "infinity";
      TimeoutStartSec = 0;
      Restart = "always";
      RestartSec = "5s";
      Environment = [
        "PATH=/var/lib/rancher/rke2/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
      ];
    };
  };

  # Service to log token location after startup
  systemd.services.rke2-token-info = {
    description = "RKE2 Token Information";
    after = [ "rke2-server.service" ];
    requires = [ "rke2-server.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = storeTokenInVault;
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 30";  # Wait for server to generate token
    };
  };

  # Ensure log directory exists
  systemd.tmpfiles.rules = [
    "d /var/log/kubernetes 0755 root root -"
  ];

  # Create symlinks for kubectl in /usr/local/bin
  system.activationScripts.rke2Links = ''
    mkdir -p /usr/local/bin
    # These will be created after RKE2 installs
  '';
}
