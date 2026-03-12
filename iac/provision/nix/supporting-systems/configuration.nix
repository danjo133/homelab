# Supporting Systems VM Configuration
# Full NixOS configuration for the support VM

{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./modules/base.nix
    ./modules/nginx.nix
    ./modules/vault.nix
    ./modules/minio.nix
    ./modules/nfs.nix
    ./modules/harbor.nix
  ];

  # Boot configuration
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/vda";
  boot.loader.timeout = 1;

  # Serial console for debugging
  boot.kernelParams = [ "console=ttyS0" ];
  boot.loader.grub.extraConfig = ''
    serial --unit=0 --speed=115200
    terminal --timeout=0 serial console
  '';

  # Networking - DHCP with gateway only on VLAN 50 interface
  networking.useDHCP = true;
  networking.dhcpcd.extraConfig = ''
    # For the first interface (libvirt NAT), don't set gateway
    interface ens6
      nogateway
    interface enp0s6
      nogateway
  '';

  # Vagrant user setup (required for vagrant ssh access)
  users.users.vagrant = {
    isNormalUser = true;
    home = "/home/vagrant";
    createHome = true;
    group = "vagrant";
    extraGroups = [ "wheel" "docker" ];
    shell = pkgs.bashInteractive;
    initialPassword = "vagrant";
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

  # SSH key for vagrant user
  system.activationScripts.vagrantSsh = ''
    mkdir -p /home/vagrant/.ssh
    chmod 700 /home/vagrant/.ssh
    echo 'ecdsa-sha2-nistp521 AAAAE2VjZHNhLXNoYTItbmlzdHA1MjEAAAAIbmlzdHA1MjEAAACFBAH5fOxrh8KGKTT+nTyjtizwysXi5aiQxHqdgXQJ7lL+yiiLIL4RpQpiu4ER6b4Qd2ufwiwphuvuVrcxGPqZTdp8yQCnYxPki8aPs36wUjhGpAJKxzPX2+Izu1DyKwKJEUJC+ko03fLYlUsMKUmPSv/QzYyypXlUBySrced0YEMTN9grvA== vagrant@homelab' > /home/vagrant/.ssh/authorized_keys
    chmod 600 /home/vagrant/.ssh/authorized_keys
    chown -R vagrant:vagrant /home/vagrant/.ssh
  '';

  # Enable SSH
  services.openssh.enable = true;
  services.openssh.settings = {
    PermitRootLogin = "yes";
    PasswordAuthentication = true;
  };

  # Allow unfree packages (Vault has BSL license)
  nixpkgs.config.allowUnfree = true;

  system.stateVersion = "25.11";
}
