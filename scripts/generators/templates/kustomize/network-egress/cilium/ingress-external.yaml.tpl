apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-external-ingress
  namespace: istio-ingress
spec:
  description: "Allow external clients to reach the Istio ingress gateway"
  endpointSelector: {}
  ingress:
    - fromEntities:
        - world
        - cluster
        - host
        - remote-node
  egress:
    - toEntities:
        - cluster
        - host
        - remote-node
