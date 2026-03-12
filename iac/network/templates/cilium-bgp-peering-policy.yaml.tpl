# CiliumBGPPeeringPolicy - Generated from config.yaml
# Do not edit directly - run: make generate-network-config
#
# Configuration:
# - Router (UniFi): {{ROUTER_IP}} with ASN {{ROUTER_ASN}}
# - Cilium nodes: ASN {{CILIUM_ASN}}
# - Advertises: LoadBalancer service IPs from CiliumLoadBalancerIPPool
#
# ASN Selection:
# Private ASN range: 64512-65534 (like 10.x.x.x for IPs - free for internal use)

apiVersion: cilium.io/v2alpha1
kind: CiliumBGPPeeringPolicy
metadata:
  name: bgp-peering-policy
spec:
  nodeSelector:
    matchLabels:
      kubernetes.io/os: linux

  virtualRouters:
    - localASN: {{CILIUM_ASN}}
      exportPodCIDR: false
      neighbors:
        - peerAddress: "{{ROUTER_IP}}/32"
          peerASN: {{ROUTER_ASN}}
      serviceSelector:
        matchExpressions:
          - key: somekey
            operator: NotIn
            values:
              - never-match-this
