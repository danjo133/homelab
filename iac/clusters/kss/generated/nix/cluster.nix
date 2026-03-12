# Auto-generated from cluster.yaml — do not edit
# Cluster: kss
{ config, lib, ... }:
{
  imports = [
    ./k8s-common/cluster-options.nix
  ];

  kss.cni = "default";

  kss.cluster = {
    name = "kss";
    domain = "simple-k8s.example.com";
    masterIp = "10.69.50.20";
    masterHostname = "kss-master";
    vaultAuthMount = "kubernetes-kss";
  };

  kss.cluster.oidc = {
    enabled = true;
    issuerUrl = "https://auth.simple-k8s.example.com/realms/broker";
    clientId = "kubernetes";
  };
}
