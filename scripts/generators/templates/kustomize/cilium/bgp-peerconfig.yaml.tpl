{{- $ctx := (ds "ctx") -}}
# Auto-generated from cluster.yaml — do not edit
# Cluster: {{ $ctx.computed.name }}
apiVersion: cilium.io/v2
kind: CiliumBGPPeerConfig
metadata:
  name: {{ (ds "ctx").computed.name }}-peer
spec:
  timers:
    connectRetryTimeSeconds: 5
    holdTimeSeconds: 90
    keepAliveTimeSeconds: 30
  ebgpMultihop: 4
  gracefulRestart:
    enabled: true
    restartTimeSeconds: 15
  families:
    - afi: ipv4
      safi: unicast
      advertisements:
        matchLabels:
          advertise: "bgp"
