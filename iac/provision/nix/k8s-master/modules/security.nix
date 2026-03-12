# Security configuration for k8s-master
# Vault CA trust and Harbor registry authentication

{ config, pkgs, lib, ... }:

{
  # Import Vault CA module
  imports = [
    ../k8s-common/vault-ca.nix
  ];

  # Harbor registry configuration for containerd/RKE2
  environment.etc."rancher/rke2/registries.yaml" = {
    mode = "0644";
    text = ''
      # Registry mirrors and authentication
      mirrors:
        # Use Harbor as a pull-through cache for Docker Hub
        docker.io:
          endpoint:
            - "https://harbor.support.example.com/v2/docker.io"
        # Direct Harbor access
        harbor.support.example.com:
          endpoint:
            - "https://harbor.support.example.com"

      configs:
        "harbor.support.example.com":
          tls:
            # Skip TLS verification for self-signed cert
            # TODO: Use Vault CA cert instead
            insecure_skip_verify: true
    '';
  };

  # Note: Harbor authentication can be added later when we have
  # a proper secrets management flow. For now, we rely on:
  # 1. Public read access to Harbor projects
  # 2. Or manual docker login on nodes if needed

  # crictl configuration to match containerd socket
  environment.etc."crictl.yaml" = {
    mode = "0644";
    text = ''
      runtime-endpoint: unix:///run/k3s/containerd/containerd.sock
      image-endpoint: unix:///run/k3s/containerd/containerd.sock
      timeout: 10
      debug: false
    '';
  };
}
