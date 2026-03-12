{ config, pkgs, lib, ... }:

# NixOS configuration for the Vagrant base box
#
# IMPORTANT: The SSH public key below must match the private key at
# ~/.vagrant.d/ecdsa_private_key on the Vagrant host. If you're setting
# up a new environment:
#
#   1. Generate a new key pair:
#      ssh-keygen -t ecdsa -b 521 -f ~/.vagrant.d/ecdsa_private_key -N "" -C "vagrant@homelab"
#
#   2. Update the public key in system.activationScripts.vagrantSsh below
#
#   3. Rebuild the box:
#      ./build-nix-box.sh
#      vagrant box add --name local/nixos-25.11-vagrant --provider libvirt nixos-25.11-vagrant.box

{
  # Basic system configuration for Vagrant box
  imports = [
    <nixpkgs/nixos/modules/profiles/qemu-guest.nix>
  ];

  # Networking configuration
  # Use DHCP on all interfaces, but configure the NAT interface to not set a default gateway
  # - First interface (libvirt NAT): DHCP for IP only, no gateway (Vagrant SSH management)
  # - Second interface (VLAN 50): DHCP with gateway (main network access)
  networking.useDHCP = true;

  # Configure dhcpcd: don't accept default gateway from libvirt NAT
  # Interface names vary (ens6/ens7 or enp0s6/enp0s7), so match by MAC prefix
  # Libvirt generates MACs starting with 52:54:00
  networking.dhcpcd.extraConfig = ''
    # For the first interface (lower PCI slot = libvirt NAT), don't set gateway
    interface ens6
      nogateway
    interface enp0s6
      nogateway
  '';

  # System packages
  environment.systemPackages = with pkgs; [
    vim
    curl
    wget
    git
    openssh
  ];

  # Enable SSH
  services.openssh.enable = true;
  services.openssh.settings = {
    PermitRootLogin = "yes";
    PasswordAuthentication = true;
  };

  # Vagrant user setup
  users.users.vagrant = {
    isNormalUser = true;
    home = "/home/vagrant";
    createHome = true;
    group = "vagrant";
    extraGroups = [ "wheel" ];
    shell = pkgs.bashInteractive;
    initialPassword = "vagrant";
  };

  users.groups.vagrant = { };

  # Vagrant user sudoers
  security.sudo.extraRules = [
    {
      users = [ "vagrant" ];
      commands = [
        { command = "ALL"; options = [ "NOPASSWD" ]; }
      ];
    }
  ];

  # SSH key for vagrant user - create .ssh directory explicitly
  # Using activation script to ensure .ssh/authorized_keys exists
  system.activationScripts.vagrantSsh = ''
    mkdir -p /home/vagrant/.ssh
    chmod 700 /home/vagrant/.ssh
    echo 'ecdsa-sha2-nistp521 AAAAE2VjZHNhLXNoYTItbmlzdHA1MjEAAAAIbmlzdHA1MjEAAACFBAH5fOxrh8KGKTT+nTyjtizwysXi5aiQxHqdgXQJ7lL+yiiLIL4RpQpiu4ER6b4Qd2ufwiwphuvuVrcxGPqZTdp8yQCnYxPki8aPs36wUjhGpAJKxzPX2+Izu1DyKwKJEUJC+ko03fLYlUsMKUmPSv/QzYyypXlUBySrced0YEMTN9grvA== vagrant@homelab' > /home/vagrant/.ssh/authorized_keys
    chmod 600 /home/vagrant/.ssh/authorized_keys
    chown -R vagrant:vagrant /home/vagrant/.ssh
  '';

  # Disable firewall for simplicity (can be enabled per-deployment)
  networking.firewall.enable = false;

  # Enable serial console for debugging
  boot.kernelParams = [ "console=ttyS0" ];
  boot.loader.grub.extraConfig = ''
    serial --unit=0 --speed=115200
    terminal --timeout=0 serial console
  '';

  # Minimal boot setup - use mkDefault to allow format overrides
  boot.loader.timeout = lib.mkDefault 1;

  # System state version
  system.stateVersion = "25.11";
}
