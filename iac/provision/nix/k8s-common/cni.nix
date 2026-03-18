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

      # Block pod traffic to router infrastructure ports.
      # NOTE: UDP DNS (port 53) is intentionally NOT blocked here because RKE2
      # CoreDNS uses pod networking (not hostNetwork) and needs to forward
      # upstream DNS queries to the gateway. DNS egress restrictions are handled
      # by K8s NetworkPolicy / CiliumNetworkPolicy instead.
      # On Cilium clusters, CiliumClusterwideNetworkPolicy handles this instead.
      networking.firewall.extraCommands =
        let
          podCidr = config.kss.cluster.podCidr;
          gwIp = config.kss.cluster.gatewayIp;
          mgmtCidr = config.kss.cluster.managementCidr;
          ollamaIp = config.kss.cluster.ollamaIp;
        in ''
          # Allow pod egress to Ollama LLM host (before management VLAN deny)
          ${lib.optionalString (ollamaIp != "") ''
          iptables -C FORWARD -s ${podCidr} -d ${ollamaIp}/32 -j ACCEPT 2>/dev/null \
            || iptables -I FORWARD -s ${podCidr} -d ${ollamaIp}/32 -j ACCEPT
          ''}
          # Block pod egress to management VLAN
          iptables -C FORWARD -s ${podCidr} -d ${mgmtCidr} -j DROP 2>/dev/null \
            || iptables -I FORWARD -s ${podCidr} -d ${mgmtCidr} -j DROP
          # Block pod egress to router management and infrastructure ports (TCP only)
          for port in 22 53 80 179 443 8443; do
            iptables -C FORWARD -s ${podCidr} -d ${gwIp}/32 -p tcp --dport $port -j DROP 2>/dev/null \
              || iptables -I FORWARD -s ${podCidr} -d ${gwIp}/32 -p tcp --dport $port -j DROP
          done
        '';
    })
  ];
}
