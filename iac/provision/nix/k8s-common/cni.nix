# CNI (Container Network Interface) configuration module
# Defines kss.cni option to switch between RKE2's default Canal and Cilium
#
# Usage: Set kss.cni = "cilium" or kss.cni = "default" in configuration.nix

{ config, pkgs, lib, ... }:

let
  isCilium = config.kss.cni == "cilium";
in
{
  options.kss = {
    cni = lib.mkOption {
      type = lib.types.enum [ "default" "cilium" ];
      default = "default";
      description = ''
        CNI plugin selection for the RKE2 cluster.

        "default" - Uses RKE2's built-in Canal CNI with kube-proxy.
        "cilium"  - Disables built-in CNI, kube-proxy replaced by Cilium.
                    Requires Cilium to be installed via Helm after cluster bootstrap.
      '';
    };
  };

  config = lib.mkMerge [
    # Cilium-specific configuration
    (lib.mkIf isCilium {
      networking.firewall.checkReversePath = "loose";

      boot.kernel.sysctl = {
        "net.ipv4.conf.all.rp_filter" = 0;
        "net.ipv4.conf.default.rp_filter" = 0;
      };

      networking.firewall.trustedInterfaces = [
        "cilium_host"
        "cilium_net"
        "cilium_vxlan"
        "cilium_wg0"
        "lxc+"
      ];

      networking.firewall.allowedTCPPorts = [
        4240    # Cilium agent health checks
        4244    # Hubble relay
        4245    # Hubble UI
      ];

      networking.firewall.allowedUDPPorts = [
        8472    # VXLAN (Cilium overlay)
        51871   # WireGuard (Cilium encryption)
      ];
    })

    # Default (Canal) configuration
    (lib.mkIf (!isCilium) {
      boot.kernel.sysctl = {
        "net.ipv4.conf.all.rp_filter" = 1;
        "net.ipv4.conf.default.rp_filter" = 1;
      };

      networking.firewall.allowedUDPPorts = [
        8472    # VXLAN (Canal overlay)
      ];

      networking.firewall.trustedInterfaces = [
        "cni0"
        "flannel.1"
      ];
    })
  ];
}
