# FRR Configuration for UniFi Dream Machine
# Generated from config.yaml + cluster.yaml files — do not edit directly
# Run: make generate-network-config
#
# Upload this file via: Settings > Routing > BGP
#
# This configures the router to:
# - Run BGP with ASN {{ROUTER_ASN}}
# - Peer with Kubernetes nodes running Cilium
# - Accept LoadBalancer VIP routes advertised by Cilium
#
# Network: VLAN {{VLAN}} ({{SUBNET}})

router bgp {{ROUTER_ASN}}
  bgp router-id {{ROUTER_ID}}
  no bgp ebgp-requires-policy

{{NETWORK_STATEMENTS}}

{{NEIGHBOR_DEFINITIONS}}

  address-family ipv4 unicast
{{NEIGHBOR_ACTIVATIONS}}
    maximum-paths {{MAX_PATHS}}
  exit-address-family
