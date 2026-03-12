# Auto-generated from cluster.yaml — do not edit
# Cluster: kss — worker-1 (kss-worker-1)
# Entry point for nixos-rebuild on the VM
{ config, pkgs, lib, ... }:
{
  imports = [
    ./k8s-worker/configuration.nix
    ./cluster.nix
  ];

  networking.hostName = lib.mkForce "kss-worker-1";
}
