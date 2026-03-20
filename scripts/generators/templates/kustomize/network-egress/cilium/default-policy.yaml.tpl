# Auto-generated from cluster.yaml + config.yaml — do not edit
# Cluster: {{ (ds "ctx").computed.name }} — Default-deny ingress/egress with baseline allows
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: default-policy
spec:
  description: "Default-deny with baseline allows for all pods"
  endpointSelector: {}
  ingress:
    # Allow from all cluster endpoints, host, and remote nodes
    - fromEntities:
        - cluster
        - host
        - remote-node
  egress:
    # DNS to kube-dns
    - toEndpoints:
        - matchLabels:
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: ANY
    # Kubernetes API server
    - toEntities:
        - kube-apiserver
    # Intra-cluster: all cluster endpoints, host, and remote nodes.
    # Uses entity-based rules (not toCIDR) for Istio Ambient compatibility —
    # ztunnel transparent proxy creates TRAFFIC_DIRECTION_UNKNOWN flows that
    # CIDR-based rules cannot match.
    - toEntities:
        - cluster
        - host
        - remote-node
