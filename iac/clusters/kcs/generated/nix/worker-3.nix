# Auto-generated from cluster.yaml — do not edit
# Cluster: kcs — worker-3 (kcs-worker-3)
# Entry point for nixos-rebuild on the VM
{ config, pkgs, lib, ... }:
{
  imports = [
    ./k8s-worker/configuration.nix
    ./cluster.nix
  ];

  networking.hostName = lib.mkForce "kcs-worker-3";
}
