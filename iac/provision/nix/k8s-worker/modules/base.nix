# Base system configuration for k8s-worker nodes
# Hostname derived from DHCP, mDNS, firewall rules for workers

{ config, pkgs, lib, ... }:

{
  # Hostname - will be set by activation script based on VM name
  # Default empty allows hostname to be set dynamically
  networking.hostName = lib.mkDefault "";

  # Enable Avahi for mDNS/DNS-SD
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      domain = true;
      workstation = true;
    };
  };

  # Firewall configuration for Kubernetes workers
  networking.firewall = {
    enable = true;
    allowPing = true;

    allowedTCPPorts = [
      22          # SSH
      10250       # kubelet API
    ];

    # NodePort range
    allowedTCPPortRanges = [
      { from = 30000; to = 32767; }
    ];

    allowedUDPPorts = [
      8472      # VXLAN (Cilium)
      51820     # WireGuard (Cilium encryption)
      51821     # WireGuard (Cilium encryption)
    ];
  };
}
