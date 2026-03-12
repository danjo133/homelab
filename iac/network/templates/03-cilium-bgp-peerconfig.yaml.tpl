---
apiVersion: cilium.io/v2
kind: CiliumBGPPeerConfig
metadata:
  name: cilium-peer
spec:
  authSecretRef: bgp-auth
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