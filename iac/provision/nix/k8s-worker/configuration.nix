# Kubernetes Worker Node Configuration
# RKE2 agent node - shared by k8s-worker-1, k8s-worker-2, k8s-worker-3

{ config, pkgs, lib, ... }:

{
  imports = [
    # Common modules
    ../common/vagrant-user.nix
    ../common/base-system.nix
    # VM-specific
    ./hardware-configuration.nix
    ../k8s-common/rke2-base.nix
    ./modules/base.nix
    ./modules/rke2-agent.nix
    ./modules/security.nix
    ./modules/storage.nix
  ];

  # Boot configuration
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/vda";

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  system.stateVersion = "25.11";
}
