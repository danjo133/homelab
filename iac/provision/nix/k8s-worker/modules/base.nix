# Base system configuration for k8s-worker nodes
# Hostname set per-worker via k8s-worker-N/configuration.nix, firewall rules for workers

{ config, pkgs, lib, ... }:

{
  # Hostname - set by k8s-worker-N/configuration.nix via mkForce
  # Default empty; will be overridden per-worker node
  networking.hostName = lib.mkDefault "";

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
