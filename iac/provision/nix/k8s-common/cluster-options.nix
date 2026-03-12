# Cluster configuration options module
# Defines kss.cluster options used by all k8s node types
# Values are set per-cluster in generated/nix/cluster.nix

{ lib, ... }:

{
  options.kss.cluster = {
    name = lib.mkOption {
      type = lib.types.str;
      description = "Cluster name (e.g. kss, kss2)";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "support.example.com";
      description = "DNS domain for the cluster";
    };

    masterIp = lib.mkOption {
      type = lib.types.str;
      description = "IP address of the master node";
    };

    masterHostname = lib.mkOption {
      type = lib.types.str;
      description = "Hostname of the master node (e.g. kss-master)";
    };

    vaultAddr = lib.mkOption {
      type = lib.types.str;
      default = "https://vault.support.example.com";
      description = "Vault server address";
    };

    harborAddr = lib.mkOption {
      type = lib.types.str;
      default = "harbor.support.example.com";
      description = "Harbor registry hostname";
    };

    vaultAuthMount = lib.mkOption {
      type = lib.types.str;
      default = "kubernetes";
      description = "Vault Kubernetes auth mount path";
    };
  };
}
