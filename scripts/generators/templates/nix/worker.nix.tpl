# Auto-generated from cluster.yaml — do not edit
# Cluster: {{ (ds "ctx").computed.name }} — {{ .Env.WORKER_NAME }} ({{ .Env.WORKER_HOSTNAME }})
# Entry point for nixos-rebuild on the VM
{ config, pkgs, lib, ... }:
{
  imports = [
    ./k8s-worker/configuration.nix
    ./cluster.nix
  ];

  networking.hostName = lib.mkForce "{{ .Env.WORKER_HOSTNAME }}";
}
