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
    domain = "kss.example.com";
    masterIp = "10.69.50.20";
    masterHostname = "kss-master";
    vaultAuthMount = "kubernetes";
    vaultNamespace = "kss";
  };

  kss.example.com = {
    enabled = true;
    issuerUrl = "https://auth.kss.example.com/realms/broker";
    clientId = "kubernetes";
  };
}
