# Auto-generated from cluster.yaml — do not edit
# Cluster: kcs — master node
# Entry point for nixos-rebuild on the VM
{ config, pkgs, lib, ... }:
{
  imports = [
    ./configuration.nix
    ./cluster.nix
  ];
}
