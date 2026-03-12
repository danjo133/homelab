# RKE2 Server (Control Plane) configuration
# Auto-installs RKE2 on first boot and starts the server

{ config, pkgs, lib, ... }:

let
  # CNI selection
  isCilium = config.kss.cni == "cilium";

  # RKE2 version
  rke2Version = "v1.31.4+rke2r1";

  # Cleanup script to kill orphaned containerd-shim processes on stop/restart.
  # RKE2 uses KillMode=process so the main rke2 process is killed, but
  # containerd-shim processes survive by design (they reparent to init).
  # Without cleanup, stale kube-apiserver/etcd/etc hold ports and block restart.
  rke2Cleanup = pkgs.writeShellScript "rke2-server-cleanup" ''
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

  # RKE2 installation script - direct download to avoid NixOS path issues
  rke2Install = pkgs.writeShellScript "rke2-server-install" ''
    set -eu

    export PATH="${lib.makeBinPath [ pkgs.curl pkgs.gnutar pkgs.gzip pkgs.coreutils pkgs.bash pkgs.gnused pkgs.gnugrep pkgs.gawk pkgs.util-linux pkgs.findutils pkgs.diffutils ]}"

    INSTALL_DIR="/opt/rke2"
    MARKER="/var/lib/rancher/rke2/.installed"
    VERSION="${rke2Version}"
    # URL-encode the + as %2B for GitHub
    VERSION_URL=$(echo "$VERSION" | sed 's/+/%2B/g')

    if [ -f "$MARKER" ]; then
      echo "RKE2 already installed"
      exit 0
    fi

    echo "Installing RKE2 server $VERSION..."

    # Create directories
    mkdir -p "$INSTALL_DIR/bin"
    mkdir -p "$INSTALL_DIR/share/rke2"
    mkdir -p /var/lib/rancher/rke2
    mkdir -p /etc/rancher/rke2
    mkdir -p /var/log/kubernetes

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
    echo "RKE2 server installation complete"
    echo "RKE2 binary at: $INSTALL_DIR/bin/rke2"
  '';

  # Cluster config
  clusterName = config.kss.cluster.name;
  masterHostname = config.kss.cluster.masterHostname;
  clusterDomain = config.kss.cluster.domain;
  vaultAddr = config.kss.cluster.vaultAddr;

  # OIDC config
  oidcEnabled = config.kss.cluster.oidc.enabled;
  oidcIssuerUrl = config.kss.cluster.oidc.issuerUrl;
  oidcClientId = config.kss.cluster.oidc.clientId;

  # Pre-formatted OIDC kube-apiserver args (indentation must match kube-apiserver-arg list items)
  oidcApiServerArgs = lib.optionalString oidcEnabled (lib.concatMapStrings (arg: "\n  - \"${arg}\"") [
    "oidc-issuer-url=${oidcIssuerUrl}"
    "oidc-client-id=${oidcClientId}"
    "oidc-username-claim=preferred_username"
    "oidc-username-prefix=oidc:"
    "oidc-groups-claim=groups"
    "oidc-groups-prefix=oidc:"
  ]);

  # Script to store token in Vault (for workers to retrieve)
  storeTokenInVault = pkgs.writeShellScript "store-rke2-token" ''
    set -eu

    export PATH="${lib.makeBinPath [ pkgs.curl pkgs.jq pkgs.coreutils]}"

    TOKEN_FILE="/var/lib/rancher/rke2/server/node-token"

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
    echo "Workers can join using: server: https://${masterHostname}:9345"
  '';
in
{
  # RKE2 server configuration file
  environment.etc."rancher/rke2/config.yaml" = {
    mode = "0644";
    text = ''
      # RKE2 Server Configuration
    '' + lib.optionalString isCilium ''
      # CNI disabled - Cilium will be installed via Helm
      cni: none

      # Disable kube-proxy - Cilium handles kube-proxy replacement
      disable-kube-proxy: true
    '' + ''

      # Node name - use hostname instead of OS transient hostname
      node-name: ${masterHostname}
    '' + lib.optionalString isCilium ''

      # Label for Cilium BGP node selector
      node-label:
        - bgp_enabled=true
    '' + ''

      # Disable default components we'll replace
      disable:
    '' + lib.optionalString isCilium ''
        - rke2-canal
    '' + ''
        - rke2-ingress-nginx

      # TLS SANs for API server certificate
      tls-san:
        - ${masterHostname}
        - ${masterHostname}.local
        - ${masterHostname}.${clusterDomain}
        - localhost
        - 127.0.0.1

      # Make kubeconfig readable for debugging
      write-kubeconfig-mode: "0644"

      # Audit logging
      kube-apiserver-arg:
        - "audit-log-path=/var/log/kubernetes/audit.log"
        - "audit-log-maxage=30"
        - "audit-log-maxbackup=10"
        - "audit-log-maxsize=100"${oidcApiServerArgs}

      # Taint control-plane node to keep workloads on workers
      node-taint:
        - "node-role.kubernetes.io/control-plane=true:NoSchedule"

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
    wantedBy = [ "rke2-server.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = rke2Install;
    };
  };

  # RKE2 server service - starts asynchronously, does not block nixos-rebuild
  systemd.services.rke2-server = {
    description = "RKE2 Kubernetes Server";
    documentation = [ "https://docs.rke2.io" ];
    after = [ "network-online.target" "rke2-server-install.service" ];
    wants = [ "network-online.target" "rke2-server-install.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "exec";
      ExecStart = "/opt/rke2/bin/rke2 server";
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

  # Service to log token location after startup
  systemd.services.rke2-token-info = {
    description = "RKE2 Token Information";
    after = [ "rke2-server.service" ];
    wants = [ "rke2-server.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = storeTokenInVault;
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 30";
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
