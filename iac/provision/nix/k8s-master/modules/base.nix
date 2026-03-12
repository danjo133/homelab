# Base system configuration for k8s-master
# Hostname, firewall rules for control plane

{ config, pkgs, lib, ... }:

{
  # Hostname - sent via DHCP to Unifi for DNS registration
  networking.hostName = "k8s-master";

  # Firewall configuration for Kubernetes control plane
  networking.firewall = {
    enable = true;
    allowPing = true;

    allowedTCPPorts = [
      22        # SSH
      80        # HTTP
      443       # HTTPS
      6443      # Kubernetes API server
      9345      # RKE2 supervisor API (for node joining)
      2379      # etcd client
      2380      # etcd peer
      10250     # kubelet API
      10251     # kube-scheduler (deprecated but may be used)
      10252     # kube-controller-manager (deprecated but may be used)
      10257     # kube-controller-manager secure
      10259     # kube-scheduler secure
    ];
  };
}
