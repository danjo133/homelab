# Common base system configuration
# Shared across all NixOS VMs
#
# This module defines:
# - Serial console for debugging
# - Basic system packages
# - DHCP networking with gateway only on VLAN interface

{ config, pkgs, lib, ... }:

{
  imports = [
    <nixpkgs/nixos/modules/profiles/qemu-guest.nix>
  ];

  # Networking - DHCP on all interfaces
  # Configure dhcpcd: don't accept default gateway from libvirt NAT (ens6)
  # Only accept gateway from VLAN 50 interface (ens7)
  networking.useDHCP = true;
  networking.dhcpcd.extraConfig = ''
    # Send hostname in DHCP requests (Option 12)
    # This allows the DHCP server (Unifi) to register our hostname
    hostname

    # For the first interface (libvirt NAT), don't set gateway or DNS
    # nogateway: don't use as default route
    # nooption domain_name_servers: don't add its DHCP nameservers to resolv.conf
    interface ens6
      nogateway
      nooption domain_name_servers
      nooption domain_name
      nooption domain_search
    interface enp0s6
      nogateway
      nooption domain_name_servers
      nooption domain_name
      nooption domain_search

    # Don't manage Cilium/container interfaces - they're managed by the CNI
    denyinterfaces cilium* lxc* veth* cni* docker* br-*
  '';

  # Basic system packages available on all VMs
  environment.systemPackages = with pkgs; [
    vim
    curl
    wget
    git
    htop
    jq
    tree
    coreutils
  ];

  # Enable serial console for debugging
  boot.kernelParams = [ "console=ttyS0" ];
  boot.loader.grub.extraConfig = ''
    serial --unit=0 --speed=115200
    terminal --timeout=0 serial console
  '';

  # Minimal boot timeout
  boot.loader.timeout = lib.mkDefault 1;

  # Timezone + NTP
  time.timeZone = "Europe/Stockholm";
  services.timesyncd = {
    enable = true;
    servers = [ "ntp.se" "time.cloudflare.com" ];
  };

  # System state version - can be overridden per-VM if needed
  system.stateVersion = lib.mkDefault "25.11";
}
