# Common Vagrant user configuration
# Shared across all NixOS VMs for consistent user setup
#
# This module defines:
# - vagrant user with passwordless sudo
# - SSH key for Vagrant access
# - Basic shell configuration
#
# The SSH public key must match the private key at ~/.vagrant.d/ecdsa_private_key
# on the Vagrant host (iter).

{ config, pkgs, lib, ... }:

{
  # Vagrant user
  users.users.vagrant = {
    isNormalUser = true;
    home = "/home/vagrant";
    createHome = true;
    group = "vagrant";
    extraGroups = [ "wheel" ];
    shell = pkgs.bashInteractive;
    initialPassword = "vagrant";
    openssh.authorizedKeys.keys = [
      "ecdsa-sha2-nistp521 AAAAE2VjZHNhLXNoYTItbmlzdHA1MjEAAAAIbmlzdHA1MjEAAACFBAH5fOxrh8KGKTT+nTyjtizwysXi5aiQxHqdgXQJ7lL+yiiLIL4RpQpiu4ER6b4Qd2ufwiwphuvuVrcxGPqZTdp8yQCnYxPki8aPs36wUjhGpAJKxzPX2+Izu1DyKwKJEUJC+ko03fLYlUsMKUmPSv/QzYyypXlUBySrced0YEMTN9grvA== vagrant@homelab"
    ];
  };

  users.groups.vagrant = {};

  # Passwordless sudo for vagrant
  security.sudo.extraRules = [
    {
      users = [ "vagrant" ];
      commands = [
        { command = "ALL"; options = [ "NOPASSWD" ]; }
      ];
    }
  ];

  # Enable SSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
  };
}
