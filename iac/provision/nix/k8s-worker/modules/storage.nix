# Storage configuration for k8s-worker nodes
# Longhorn prerequisites and NFS client configuration

{ config, pkgs, lib, ... }:

{
  # Additional kernel modules for storage (iscsi_tcp is in rke2-base.nix)
  boot.kernelModules = [
    "dm_crypt"      # For encrypted volumes
    "dm_snapshot"   # For snapshots
  ];

  # NFS client packages (already in rke2-base, but explicit here)
  environment.systemPackages = with pkgs; [
    nfs-utils
    openiscsi
    lvm2
    e2fsprogs
    xfsprogs
    util-linux  # for blkid, etc
  ];

  # Multipath for iSCSI (optional but recommended for Longhorn)
  # services.multipathd.enable = true;

  # Directory for Longhorn data (iscsid + symlinks are in rke2-base.nix)
  systemd.tmpfiles.rules = [
    "d /var/lib/longhorn 0755 root root -"
  ];

  # NFS mount points for support VM
  # These can be used for RWX volumes or backups
  fileSystems."/mnt/nfs/kubernetes-rwx" = {
    device = "support.local:/export/kubernetes-rwx";
    fsType = "nfs";
    options = [
      "nfsvers=4"
      "soft"
      "timeo=30"
      "retrans=3"
      "noauto"        # Don't mount at boot (mount when needed)
      "x-systemd.automount"
      "x-systemd.idle-timeout=300"
    ];
  };

  fileSystems."/mnt/nfs/backups" = {
    device = "support.local:/export/backups";
    fsType = "nfs";
    options = [
      "nfsvers=4"
      "soft"
      "timeo=30"
      "retrans=3"
      "noauto"
      "x-systemd.automount"
      "x-systemd.idle-timeout=300"
    ];
  };
}
