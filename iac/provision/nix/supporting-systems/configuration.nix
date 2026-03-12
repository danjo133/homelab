# Supporting Systems VM Configuration
# Full NixOS configuration for the support VM

{ config, pkgs, lib, ... }:

{
  imports = [
    # Common modules
    ../common/vagrant-user.nix
    ../common/base-system.nix
    # VM-specific
    ./hardware-configuration.nix
    ./modules/base.nix
    ./modules/nginx.nix      # Uses self-signed certs by default
    ./modules/openbao.nix
    ./modules/minio.nix
    ./modules/nfs.nix
    ./modules/harbor.nix
    ./modules/keycloak.nix
    ./modules/teleport.nix
    ./modules/gitlab.nix

    # OPTIONAL: Uncomment for Let's Encrypt certificates
    # Requires: sops-nix setup with Cloudflare API token
    # See .sops.yaml at repo root for setup instructions
    ./modules/sops.nix
    ./modules/acme.nix
  ];

  # Boot configuration
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/vda";

  # Add docker group to vagrant user (for Harbor management)
  users.users.vagrant.extraGroups = lib.mkAfter [ "docker" ];

  # Allow unfree packages (some dependencies may require it)
  nixpkgs.config.allowUnfree = true;

  system.stateVersion = "25.11";
}
