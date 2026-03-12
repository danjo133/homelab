# Kubernetes Worker Node 3 Configuration
# Wrapper that sets hostname and imports shared worker config

{ config, pkgs, lib, ... }:

{
  imports = [
    ../k8s-worker/configuration.nix
  ];

  # Set hostname for this specific worker
  networking.hostName = lib.mkForce "k8s-worker-3";
}
