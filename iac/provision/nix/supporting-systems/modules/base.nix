# Base system configuration for support VM
# Hostname, common packages, firewall base

{ config, pkgs, lib, ... }:

{
  # Hostname - sent via DHCP to Unifi for DNS registration
  networking.hostName = "support";

  # Common packages needed for administration and services
  environment.systemPackages = with pkgs; [
    # System utilities
    vim
    htop
    curl
    wget
    jq
    git
    tree
    rsync

    # Network tools
    dig
    tcpdump
    netcat-gnu

    # TLS/Certificate tools
    openssl

    # MinIO client
    minio-client

    # Docker tools (for Harbor)
    docker-compose
  ];

  # System limits for services
  security.pam.loginLimits = [
    { domain = "*"; type = "soft"; item = "nofile"; value = "65535"; }
    { domain = "*"; type = "hard"; item = "nofile"; value = "65535"; }
  ];

  # Firewall configuration - base rules
  # Each service module adds its own allowed ports
  networking.firewall = {
    enable = true;
    allowPing = true;

    # Common ports
    allowedTCPPorts = [
      22    # SSH
      80    # HTTP (redirect to HTTPS)
      443   # HTTPS (Nginx)
    ];
  };

  # Ensure time sync is enabled
  services.timesyncd.enable = true;
}
