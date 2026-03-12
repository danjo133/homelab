# Security configuration for k8s-worker nodes
# Vault CA trust and Harbor registry authentication

{ config, pkgs, lib, ... }:

let
  harborAddr = config.kss.cluster.harborAddr;
in
{
  # Import Vault CA module
  imports = [
    ../../k8s-common/vault-ca.nix
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
            - "https://${harborAddr}/v2/docker.io"
        # Direct Harbor access
        ${harborAddr}:
          endpoint:
            - "https://${harborAddr}"

      configs:
        "${harborAddr}":
          tls:
            # Skip TLS verification for self-signed cert
            # TODO: Use Vault CA cert instead
            insecure_skip_verify: true
    '';
  };

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
