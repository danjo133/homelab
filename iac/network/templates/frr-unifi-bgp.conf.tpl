# FRR Configuration for UniFi Dream Machine
# Generated from config.yaml - Do not edit directly
# Run: make generate-network-config
#
# Upload this file via: Settings > Routing > BGP
#
# This configures the router to:
# - Run BGP with ASN {{ROUTER_ASN}}
# - Peer with Kubernetes nodes running Cilium (ASN {{CILIUM_ASN}})
# - Accept LoadBalancer VIP routes advertised by Cilium
#
# Network: VLAN {{VLAN}} ({{SUBNET}})
# LoadBalancer VIPs: {{LB_START}}-{{LB_STOP_LAST_OCTET}}

router bgp {{ROUTER_ASN}}
  bgp router-id {{ROUTER_ID}}
  no bgp ebgp-requires-policy

  network {{LB_RANGE}}

{{NEIGHBOR_DEFINITIONS}}

  address-family ipv4 unicast
{{NEIGHBOR_ACTIVATIONS}}
    maximum-paths 4
  exit-address-family
