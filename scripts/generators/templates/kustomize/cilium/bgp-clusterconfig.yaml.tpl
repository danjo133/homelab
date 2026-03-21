{{- $ctx := (ds "ctx") -}}
# Auto-generated from cluster.yaml — do not edit
# Cluster: {{ $ctx.computed.name }}
apiVersion: cilium.io/v2
kind: CiliumBGPClusterConfig
metadata:
  name: {{ (ds "ctx").computed.name }}-bgp
spec:
  nodeSelector:
    matchLabels:
      bgp_enabled: "true"
  bgpInstances:
    - name: "instance-{{ (ds "ctx").cluster.bgp.asn }}"
      localASN: {{ (ds "ctx").cluster.bgp.asn }}
      peers:
        - name: "peer-router"
          peerAddress: "{{ (ds "ctx").config.gatewayIp }}"
          peerASN: 64512
          peerConfigRef:
            name: "{{ (ds "ctx").computed.name }}-peer"
