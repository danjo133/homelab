# Auto-generated from cluster.yaml — do not edit
# Cluster: kcs
{ config, lib, ... }:
{
  imports = [
    ./k8s-common/cluster-options.nix
  ];

  kss.cni = "cilium";

  kss.cluster = {
    name = "kcs";
    domain = "mesh-k8s.example.com";
    masterIp = "10.69.50.50";
    masterHostname = "kcs-master";
    vaultAuthMount = "kubernetes-kcs";
  };
}
