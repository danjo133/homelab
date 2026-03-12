# Base system configuration for support VM
# Hostname, mDNS, common packages, firewall base

{ config, pkgs, lib, ... }:

{
  # Hostname - will be advertised via mDNS
  networking.hostName = "support";

  # Enable Avahi for mDNS/DNS-SD
  # This allows the VM to register as support.local on the network
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      domain = true;
      workstation = true;
    };
  };

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
