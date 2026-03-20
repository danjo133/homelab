apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Auto-generated from cluster.yaml — do not edit
# Cluster: {{ (ds "ctx").computed.name }} — Cilium BGP + LoadBalancer config

resources:
  - loadbalancer-pool.yaml
  - bgp-advertisement.yaml
  - bgp-peerconfig.yaml
  - bgp-clusterconfig.yaml
