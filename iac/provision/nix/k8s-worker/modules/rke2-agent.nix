# RKE2 Agent configuration for worker nodes
# Auto-installs RKE2 agent and joins the cluster

{ config, pkgs, lib, ... }:

let
  # RKE2 version - must match master
  rke2Version = "v1.31.4+rke2r1";

  # RKE2 agent installation script
  rke2Install = pkgs.writeShellScript "rke2-agent-install" ''
    set -eu

    export PATH="${lib.makeBinPath [ pkgs.curl pkgs.gnutar pkgs.gzip pkgs.coreutils pkgs.bash pkgs.gnused pkgs.util-linux pkgs.gnugrep pkgs.findutils pkgs.gawk pkgs.diffutils ]}"

    MARKER="/var/lib/rancher/rke2/.installed"

    if [ -f "$MARKER" ]; then
      echo "RKE2 already installed"
      exit 0
    fi

    echo "Installing RKE2 agent ${rke2Version}..."

    # Create directories
    mkdir -p /var/lib/rancher/rke2
    mkdir -p /etc/rancher/rke2

    # Download RKE2 installer
    curl -sfL https://get.rke2.io -o /tmp/rke2-install.sh

    # Install RKE2 agent
    INSTALL_RKE2_VERSION="${rke2Version}" \
    INSTALL_RKE2_TYPE="agent" \
      bash /tmp/rke2-install.sh

    rm -f /tmp/rke2-install.sh

    # Mark installation complete
    touch "$MARKER"
    echo "RKE2 agent installation complete"
  '';

  # Script to configure agent with token from shared file
  configureAgent = pkgs.writeShellScript "rke2-agent-configure" ''
    set -eu

    export PATH="${lib.makeBinPath [ pkgs.coreutils pkgs.gawk pkgs.glibc.bin ]}"

    CONFIG_FILE="/etc/rancher/rke2/config.yaml"
    TOKEN_FILE="/var/lib/rancher/rke2/shared-token"
    TOKEN_MARKER="/etc/rancher/rke2/.token-configured"

    if [ -f "$TOKEN_MARKER" ]; then
      echo "Agent already configured"
      exit 0
    fi

    echo "Configuring RKE2 agent..."

    # Wait for token file (distributed by 'make k8s-distribute-token')
    echo "Waiting for token file at $TOKEN_FILE..."
    ATTEMPTS=0
    MAX_ATTEMPTS=120  # 10 minutes

    while [ ! -f "$TOKEN_FILE" ]; do
      ATTEMPTS=$((ATTEMPTS + 1))
      if [ $ATTEMPTS -ge $MAX_ATTEMPTS ]; then
        echo "ERROR: Token file not found after $MAX_ATTEMPTS attempts"
        echo "Run 'make k8s-distribute-token' from the project root"
        exit 1
      fi
      echo "  Attempt $ATTEMPTS/$MAX_ATTEMPTS - waiting for token..."
      sleep 5
    done

    TOKEN=$(cat "$TOKEN_FILE")

    if [ -z "$TOKEN" ]; then
      echo "ERROR: Token file is empty"
      exit 1
    fi

    echo "Token found, writing config..."

    # Get master IP - use /etc/hosts or resolve k8s-master.local
    # Note: mDNS doesn't work inside RKE2's load balancer, so we need the IP
    MASTER_IP=$(getent hosts k8s-master.local | awk '{print $1}' | head -1)
    if [ -z "$MASTER_IP" ]; then
      MASTER_IP=$(getent hosts k8s-master | awk '{print $1}' | head -1)
    fi
    if [ -z "$MASTER_IP" ]; then
      echo "ERROR: Could not resolve k8s-master IP address"
      echo "Add k8s-master to /etc/hosts or ensure mDNS is working"
      exit 1
    fi
    echo "Resolved k8s-master to $MASTER_IP"

    # Write config file with token and resolved IP
    cat > "$CONFIG_FILE" << EOF
# RKE2 Agent Configuration
server: https://$MASTER_IP:9345
token: $TOKEN
EOF

    touch "$TOKEN_MARKER"
    echo "Agent configuration complete"
  '';
in
{
  # RKE2 installation service
  systemd.services.rke2-agent-install = {
    description = "RKE2 Agent Installation";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    before = [ "rke2-agent-configure.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = rke2Install;
    };
  };

  # Agent configuration service (reads token from shared file)
  systemd.services.rke2-agent-configure = {
    description = "RKE2 Agent Configuration";
    after = [ "network-online.target" "rke2-agent-install.service" ];
    wants = [ "network-online.target" ];
    requires = [ "rke2-agent-install.service" ];
    before = [ "rke2-agent.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = configureAgent;
    };
  };

  # RKE2 agent service
  systemd.services.rke2-agent = {
    description = "RKE2 Kubernetes Agent";
    documentation = [ "https://docs.rke2.io" ];
    after = [ "network-online.target" "rke2-agent-configure.service" ];
    wants = [ "network-online.target" ];
    requires = [ "rke2-agent-configure.service" ];
    wantedBy = [ "multi-user.target" ];

    # Don't start if config doesn't have a token
    unitConfig = {
      ConditionPathExists = "/etc/rancher/rke2/.token-configured";
    };

    serviceConfig = {
      Type = "notify";
      # RKE2 installs to /opt/rke2 on NixOS since /usr/local is read-only
      ExecStart = "/opt/rke2/bin/rke2 agent";
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
}
