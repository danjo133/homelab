apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: ztunnel-mesh
  namespace: istio-system
spec:
  description: "Allow ztunnel transparent proxy full mesh access"
  endpointSelector:
    matchLabels:
      app: ztunnel
  ingress:
    - fromEntities:
        - cluster
        - host
        - remote-node
        - world
  egress:
    - toEntities:
        - cluster
        - host
        - remote-node
        - world
