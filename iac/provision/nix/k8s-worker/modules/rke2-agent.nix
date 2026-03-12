# RKE2 Agent configuration for worker nodes
# Auto-installs RKE2 agent and joins the cluster

{ config, pkgs, lib, ... }:

let
  # CNI selection
  isCilium = config.kss.cni == "cilium";

  # RKE2 version - must match master
  rke2Version = "v1.31.4+rke2r1";

  # Cleanup script to kill orphaned containerd-shim processes on stop/restart.
  rke2Cleanup = pkgs.writeShellScript "rke2-agent-cleanup" ''
    export PATH="${lib.makeBinPath [ pkgs.coreutils pkgs.procps pkgs.gnused pkgs.gnugrep pkgs.util-linux pkgs.gawk pkgs.findutils ]}"

    RKE2_DATA_DIR="/var/lib/rancher/rke2"

    # Kill all containerd-shim processes spawned by RKE2
    SHIM_PIDS=$(ps -e -o pid= -o args= | sed -e 's/^ *//; s/\s\s*/\t/;' | grep -w "$RKE2_DATA_DIR/data/[^/]*/bin/containerd-shim" | cut -f1)
    if [ -n "$SHIM_PIDS" ]; then
      echo "Killing orphaned containerd-shim processes: $SHIM_PIDS"
      kill -9 $SHIM_PIDS 2>/dev/null || true
    fi

    # Unmount kubelet and CNI mounts
    for mount_prefix in /run/k3s /var/lib/kubelet/pods /run/netns/cni-; do
      MOUNTS=$(awk -v prefix="$mount_prefix" '$2 ~ "^"prefix {print $2}' /proc/self/mounts | sort -r)
      if [ -n "$MOUNTS" ]; then
        umount -- $MOUNTS 2>/dev/null || true
      fi
    done
  '';

  # RKE2 agent installation script - direct download to avoid NixOS path issues
  rke2Install = pkgs.writeShellScript "rke2-agent-install" ''
    set -eu

    export PATH="${lib.makeBinPath [ pkgs.curl pkgs.gnutar pkgs.gzip pkgs.coreutils pkgs.bash pkgs.gnused pkgs.util-linux pkgs.gnugrep pkgs.findutils pkgs.gawk pkgs.diffutils ]}"

    INSTALL_DIR="/opt/rke2"
    MARKER="/var/lib/rancher/rke2/.installed"
    VERSION="${rke2Version}"
    # URL-encode the + as %2B for GitHub
    VERSION_URL=$(echo "$VERSION" | sed 's/+/%2B/g')

    if [ -f "$MARKER" ]; then
      echo "RKE2 already installed"
      exit 0
    fi

    echo "Installing RKE2 agent $VERSION..."

    # Create directories
    mkdir -p "$INSTALL_DIR/bin"
    mkdir -p "$INSTALL_DIR/share/rke2"
    mkdir -p /var/lib/rancher/rke2
    mkdir -p /etc/rancher/rke2

    # Download RKE2 tarball
    TARBALL_URL="https://github.com/rancher/rke2/releases/download/$VERSION_URL/rke2.linux-amd64.tar.gz"
    CHECKSUM_URL="https://github.com/rancher/rke2/releases/download/$VERSION_URL/sha256sum-amd64.txt"

    echo "Downloading RKE2 from $TARBALL_URL..."
    for attempt in 1 2 3 4 5; do
      if curl -sfL "$TARBALL_URL" -o /tmp/rke2.tar.gz && \
         curl -sfL "$CHECKSUM_URL" -o /tmp/sha256sum.txt; then
        break
      fi
      echo "Download attempt $attempt failed, retrying in 10s..."
      rm -f /tmp/rke2.tar.gz /tmp/sha256sum.txt
      sleep 10
      if [ "$attempt" -eq 5 ]; then
        echo "ERROR: Failed to download RKE2 after 5 attempts"
        exit 1
      fi
    done

    # Verify checksum
    echo "Verifying checksum..."
    EXPECTED_SUM=$(grep "rke2.linux-amd64.tar.gz" /tmp/sha256sum.txt | awk '{print $1}')
    ACTUAL_SUM=$(sha256sum /tmp/rke2.tar.gz | awk '{print $1}')
    if [ "$EXPECTED_SUM" != "$ACTUAL_SUM" ]; then
      echo "ERROR: Checksum mismatch!"
      echo "Expected: $EXPECTED_SUM"
      echo "Actual:   $ACTUAL_SUM"
      exit 1
    fi
    echo "Checksum verified."

    # Extract to install directory
    echo "Extracting to $INSTALL_DIR..."
    tar -xzf /tmp/rke2.tar.gz -C "$INSTALL_DIR"

    # Clean up
    rm -f /tmp/rke2.tar.gz /tmp/sha256sum.txt

    # Make binaries executable
    chmod +x "$INSTALL_DIR/bin/"*

    # Create symlinks in /var/lib/rancher/rke2/bin for compatibility
    ln -sf "$INSTALL_DIR/bin/rke2" /var/lib/rancher/rke2/bin/rke2 || true

    # Mark installation complete
    touch "$MARKER"
    echo "RKE2 agent installation complete"
    echo "RKE2 binary at: $INSTALL_DIR/bin/rke2"
  '';

  # Cluster config
  masterHostname = config.kss.cluster.masterHostname;
  clusterDomain = config.kss.cluster.domain;
  masterFqdn = "${masterHostname}.${clusterDomain}";

  # Script to configure agent with token from shared file
  configureAgent = pkgs.writeShellScript "rke2-agent-configure" (''
    set -eu

    export PATH="${lib.makeBinPath [ pkgs.coreutils pkgs.gawk pkgs.dnsutils ]}"

    CONFIG_FILE="/etc/rancher/rke2/config.yaml"
    TOKEN_FILE="/var/lib/rancher/rke2/shared-token"
    TOKEN_MARKER="/etc/rancher/rke2/.token-configured"

    if [ -f "$TOKEN_MARKER" ]; then
      # Check if the token has changed (new master deployment)
      if [ -f "$TOKEN_FILE" ]; then
        NEW_TOKEN=$(cat "$TOKEN_FILE")
        OLD_TOKEN=$(awk '/^token:/ {print $2}' "$CONFIG_FILE" 2>/dev/null || true)
        if [ -n "$OLD_TOKEN" ] && [ "$NEW_TOKEN" != "$OLD_TOKEN" ]; then
          echo "Token changed - reconfiguring agent..."
          rm -f "$TOKEN_MARKER"
          rm -f /etc/rancher/node/password
          rm -rf /var/lib/rancher/rke2/agent
        else
          echo "Agent already configured"
          exit 0
        fi
      else
        echo "Agent already configured"
        exit 0
      fi
    fi

    # Clean stale node password from previous cluster
    rm -f /etc/rancher/node/password

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

    # Resolve master IP via dig (avoids getent/glibc issues on NixOS)
    MASTER_IP=$(dig +short ${masterFqdn} 2>/dev/null | head -1)
    if [ -z "$MASTER_IP" ]; then
      MASTER_IP=$(dig +short ${masterHostname} 2>/dev/null | head -1)
    fi
    if [ -z "$MASTER_IP" ]; then
      # Fallback: try /etc/hosts directly
      MASTER_IP=$(awk '/${masterHostname}/ {print $1; exit}' /etc/hosts 2>/dev/null)
    fi
    if [ -z "$MASTER_IP" ]; then
      echo "ERROR: Could not resolve ${masterHostname} IP address"
      echo "Add ${masterHostname} to /etc/hosts or configure DNS"
      exit 1
    fi
    echo "Resolved ${masterHostname} to $MASTER_IP"

    # Get the static hostname for node-name
    NODE_NAME=$(cat /etc/hostname 2>/dev/null || hostname)

    # Write config file with token and resolved IP
    cat > "$CONFIG_FILE" << EOF
# RKE2 Agent Configuration
server: https://$MASTER_IP:9345
token: $TOKEN
node-name: $NODE_NAME
EOF
  '' + lib.optionalString isCilium ''
    # Add BGP label for Cilium BGP node selector
    cat >> "$CONFIG_FILE" << EOF
node-label:
  - bgp_enabled=true
EOF
  '' + ''

    touch "$TOKEN_MARKER"
    echo "Agent configuration complete"
  '');
in
{
  # RKE2 installation service
  systemd.services.rke2-agent-install = {
    description = "RKE2 Agent Installation";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    before = [ "rke2-agent-configure.service" ];
    wantedBy = [ "rke2-agent.service" ];

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
    wantedBy = [ "rke2-agent.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = configureAgent;
    };
  };

  # RKE2 agent service - starts asynchronously, does not block nixos-rebuild
  systemd.services.rke2-agent = {
    description = "RKE2 Kubernetes Agent";
    documentation = [ "https://docs.rke2.io" ];
    after = [ "network-online.target" "rke2-agent-configure.service" ];
    wants = [ "network-online.target" "rke2-agent-install.service" "rke2-agent-configure.service" ];
    wantedBy = [ "multi-user.target" ];

    # Don't start if config doesn't have a token
    unitConfig = {
      ConditionPathExists = "/etc/rancher/rke2/.token-configured";
    };

    serviceConfig = {
      Type = "exec";
      ExecStart = "/opt/rke2/bin/rke2 agent";
      ExecStopPost = "-${rke2Cleanup}";
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
        "PATH=/run/wrappers/bin:/run/current-system/sw/bin:/var/lib/rancher/rke2/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
      ];
    };
  };
}
