# Nginx reverse proxy configuration
# TLS termination for all services
#
# By default uses self-signed certificates (works out of box)
# For Let's Encrypt, also import ./acme.nix (requires sops setup)

{ config, pkgs, lib, ... }:

let
  # Certificate paths (self-signed by default, overridden by acme.nix)
  certDir = "/etc/nginx/ssl";
  certFile = "${certDir}/wildcard.crt";
  keyFile = "${certDir}/wildcard.key";
  domain = "support.example.com";

  # Script to generate self-signed wildcard certificate
  generateCerts = pkgs.writeShellScript "generate-nginx-certs" ''
    set -eu
    CERT_DIR="${certDir}"
    CERT_FILE="${certFile}"
    KEY_FILE="${keyFile}"
    DOMAIN="${domain}"

    # Only generate if certs don't exist
    if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
      echo "SSL certificates already exist, skipping generation"
      exit 0
    fi

    echo "Generating self-signed wildcard certificate for *.$DOMAIN"
    mkdir -p "$CERT_DIR"

    ${pkgs.openssl}/bin/openssl req -x509 \
      -nodes \
      -days 365 \
      -newkey rsa:4096 \
      -keyout "$KEY_FILE" \
      -out "$CERT_FILE" \
      -subj "/CN=*.$DOMAIN" \
      -addext "subjectAltName=DNS:*.$DOMAIN,DNS:$DOMAIN"

    chown nginx:nginx "$KEY_FILE" "$CERT_FILE"
    chmod 640 "$KEY_FILE"
    chmod 644 "$CERT_FILE"

    echo "Certificate generated successfully"
  '';
in
{
  # Nginx reverse proxy
  services.nginx = {
    enable = true;

    # Recommended settings
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    # Logging
    commonHttpConfig = ''
      log_format main '$remote_addr - $remote_user [$time_local] '
                      '"$request" $status $body_bytes_sent '
                      '"$http_referer" "$http_user_agent"';
      access_log /var/log/nginx/access.log main;
    '';

    # Default server - return 444 for unknown hosts
    virtualHosts."_" = {
      default = true;
      locations."/".return = "444";
    };

    # Vault UI and API
    virtualHosts."vault.support.example.com" = {
      forceSSL = true;
      sslCertificate = lib.mkDefault certFile;
      sslCertificateKey = lib.mkDefault keyFile;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8200";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_read_timeout 90;
        '';
      };
    };

    # MinIO API
    virtualHosts."minio.support.example.com" = {
      forceSSL = true;
      sslCertificate = lib.mkDefault certFile;
      sslCertificateKey = lib.mkDefault keyFile;
      locations."/" = {
        proxyPass = "http://127.0.0.1:9000";
        extraConfig = ''
          # Required for MinIO to function properly
          chunked_transfer_encoding off;
          proxy_buffering off;
          proxy_request_buffering off;

          # Large uploads
          client_max_body_size 0;
        '';
      };
    };

    # MinIO Console
    virtualHosts."minio-console.support.example.com" = {
      forceSSL = true;
      sslCertificate = lib.mkDefault certFile;
      sslCertificateKey = lib.mkDefault keyFile;
      locations."/" = {
        proxyPass = "http://127.0.0.1:9001";
        proxyWebsockets = true;
      };
    };

    # Harbor Registry
    virtualHosts."harbor.support.example.com" = {
      forceSSL = true;
      sslCertificate = lib.mkDefault certFile;
      sslCertificateKey = lib.mkDefault keyFile;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8080";
        extraConfig = ''
          # For Docker push/pull (large images)
          client_max_body_size 0;
          proxy_request_buffering off;
        '';
      };
      # Harbor also needs v2 API endpoint
      locations."/v2/" = {
        proxyPass = "http://127.0.0.1:8080/v2/";
        extraConfig = ''
          # For Docker push/pull (large images)
          client_max_body_size 0;
          proxy_request_buffering off;
        '';
      };
    };
  };

  # Ensure certificate directory exists
  systemd.tmpfiles.rules = [
    "d ${certDir} 0750 nginx nginx -"
  ];

  # Auto-generate self-signed certificates before nginx starts
  # (disabled if acme.nix is imported)
  systemd.services.nginx-cert-gen = {
    description = "Generate Nginx SSL certificates";
    before = [ "nginx.service" ];
    wantedBy = [ "nginx.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = generateCerts;
      RemainAfterExit = true;
    };
  };
}
