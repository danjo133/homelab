# Auto-generated from cluster.yaml — do not edit
# Cluster: kss — worker-3 (kss-worker-3)
# Entry point for nixos-rebuild on the VM
{ config, pkgs, lib, ... }:
{
  imports = [
    ./k8s-worker/configuration.nix
    ./cluster.nix
  ];

  networking.hostName = lib.mkForce "kss-worker-3";
}
