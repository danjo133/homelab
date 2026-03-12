# NFS server configuration for Kubernetes persistent volumes

{ config, pkgs, lib, ... }:

let
  # Export paths
  nfsExportDir = "/export";
  k8sRwxDir = "${nfsExportDir}/kubernetes-rwx";
  backupsDir = "${nfsExportDir}/backups";
  longhornDir = "${nfsExportDir}/longhorn";

  # Allowed network - VLAN 50 CIDR
  allowedNetwork = "10.69.50.0/24";
in
{
  # Enable NFS server
  services.nfs.server = {
    enable = true;

    # Fixed ports for firewall compatibility
    lockdPort = 4001;
    mountdPort = 4002;
    statdPort = 4000;

    # NFS exports configuration
    exports = ''
      # Kubernetes RWX volumes
      # Options:
      # - rw: read-write access
      # - sync: synchronous writes for data safety
      # - no_subtree_check: improves reliability
      # - no_root_squash: allow root access from k8s nodes
      # - insecure: allow connections from ports > 1024
      ${k8sRwxDir}  ${allowedNetwork}(rw,sync,no_subtree_check,no_root_squash,insecure)

      # Backup storage
      # - root_squash: map root to nobody for security
      ${backupsDir}  ${allowedNetwork}(rw,sync,no_subtree_check,root_squash,insecure)

      # Longhorn backup target
      # - no_root_squash: Longhorn runs as root inside pods
      ${longhornDir}  ${allowedNetwork}(rw,sync,no_subtree_check,no_root_squash,insecure)
    '';
  };

  # Create export directories
  systemd.tmpfiles.rules = [
    "d ${nfsExportDir} 0755 root root -"
    "d ${k8sRwxDir} 0777 nobody nogroup -"
    "d ${backupsDir} 0755 root root -"
    "d ${longhornDir} 0755 root root -"
  ];

  # Firewall rules for NFS
  networking.firewall = {
    allowedTCPPorts = [
      111   # portmapper/rpcbind
      2049  # nfs
      4000  # statd
      4001  # lockd
      4002  # mountd
    ];
    allowedUDPPorts = [
      111   # portmapper/rpcbind
      2049  # nfs
      4000  # statd
      4001  # lockd
      4002  # mountd
    ];
  };
}
