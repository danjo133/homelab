# Common RKE2 configuration shared between master and workers
# Includes kernel modules, sysctl settings, and common packages

{ config, pkgs, lib, ... }:

{
  # Kernel modules required for container networking
  boot.kernelModules = [
    "overlay"
    "br_netfilter"
    "ip_tables"
    "ip6_tables"
    "iptable_nat"
    "iptable_mangle"
    "iptable_filter"
    "nf_nat"
    "nf_conntrack"
  ];

  # Sysctl settings for Kubernetes networking
  boot.kernel.sysctl = {
    # Enable IP forwarding (required for pod networking)
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;

    # Bridge settings (required for CNI)
    "net.bridge.bridge-nf-call-iptables" = 1;
    "net.bridge.bridge-nf-call-ip6tables" = 1;

    # Increase inotify limits (for many pods watching files)
    "fs.inotify.max_user_watches" = 1048576;
    "fs.inotify.max_user_instances" = 8192;

    # Increase file descriptor limits
    "fs.file-max" = 2097152;

    # Network tuning
    "net.core.somaxconn" = 32768;
    "net.ipv4.tcp_max_syn_backlog" = 32768;
    "net.core.netdev_max_backlog" = 32768;

    # Connection tracking
    "net.netfilter.nf_conntrack_max" = 1048576;
  };

  # Common packages for all k8s nodes
  environment.systemPackages = with pkgs; [
    # System utilities
    vim
    htop
    curl
    wget
    jq
    git
    tree
    rsync

    # Required by kubelet for mounting volumes
    util-linux  # provides mount, umount, etc.

    # Network tools
    dig
    tcpdump
    netcat-gnu
    iptables

    # TLS/Certificate tools
    openssl

    # Container tools (for debugging)
    cri-tools  # provides crictl

    # NFS client
    nfs-utils
  ];

  # System limits for container workloads
  security.pam.loginLimits = [
    { domain = "*"; type = "soft"; item = "nofile"; value = "1048576"; }
    { domain = "*"; type = "hard"; item = "nofile"; value = "1048576"; }
    { domain = "*"; type = "soft"; item = "nproc"; value = "unlimited"; }
    { domain = "*"; type = "hard"; item = "nproc"; value = "unlimited"; }
    { domain = "*"; type = "soft"; item = "memlock"; value = "unlimited"; }
    { domain = "*"; type = "hard"; item = "memlock"; value = "unlimited"; }
  ];

  # Enable time sync
  services.timesyncd.enable = true;

  # Disable swap (required for Kubernetes)
  # TODO: answer why this is required?
  swapDevices = lib.mkForce [];

  # RKE2 data directory
  systemd.tmpfiles.rules = [
    "d /var/lib/rancher 0755 root root -"
    "d /var/lib/rancher/rke2 0755 root root -"
    "d /etc/rancher 0755 root root -"
    "d /etc/rancher/rke2 0755 root root -"
  ];

  # Environment variables for RKE2 binaries
  environment.variables = {
    KUBECONFIG = "/etc/rancher/rke2/rke2.yaml";
  };

  # Add RKE2 bin directory to PATH via profile
  environment.etc."profile.d/rke2.sh" = {
    mode = "0644";
    text = ''
      export PATH=$PATH:/var/lib/rancher/rke2/bin
      export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
    '';
  };
}
