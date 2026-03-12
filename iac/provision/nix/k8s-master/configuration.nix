# Kubernetes Master Node Configuration
# RKE2 control plane node

{ config, pkgs, lib, ... }:

{
  imports = [
    # Common modules
    ../common/vagrant-user.nix
    ../common/base-system.nix
    # VM-specific
    ./hardware-configuration.nix
    ./k8s-common/rke2-base.nix
    ./modules/base.nix
    ./modules/rke2-server.nix
    ./modules/security.nix
  ];

  # Boot configuration
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/vda";

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  system.stateVersion = "25.11";
}
