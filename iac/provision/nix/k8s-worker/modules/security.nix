# Security configuration for k8s-worker nodes
# Vault CA trust, Harbor registry mirrors, crictl config

{ config, pkgs, lib, ... }:

{
  imports = [
    ../../k8s-common/vault-ca.nix
    ../../k8s-common/registry-mirrors.nix
  ];

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
