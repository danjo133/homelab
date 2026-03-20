apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: allow-ambient-hostprobes
spec:
  description: "Allow Istio ambient ztunnel health probe SNAT traffic"
  endpointSelector: {}
  ingress:
    - fromCIDR:
        - "169.254.7.127/32"
