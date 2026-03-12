# CiliumBGPPClusterConfig - Generated from config.yaml
# Do not edit directly - run: make generate-network-config
# could be changed to a node label for only exposing bgp on certain hosts
#
# ASN Selection:
# Private ASN range: 64512-65534 (like 10.x.x.x for IPs - free for internal use)
---
apiVersion: cilium.io/v2
kind: CiliumBGPClusterConfig
metadata:
  name: cilium-bgp
spec:
  nodeSelector:
    matchLabels:
      bgp_enabled: "true"

  bgpInstances:
    - name: "instance-{{CILIUM_ASN}}"
      localASN: {{CILIUM_ASN}}
      peers:
        - name: "peer-{{ROUTER_ASN}}-unifi"
          peerAddress: "{{ROUTER_IP}}"
          peerASN: {{ROUTER_ASN}}
          peerConfigRef:
            name: "cilium-peer"