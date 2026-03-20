apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Auto-generated from cluster.yaml — do not edit
# Cluster: {{ (ds "ctx").computed.name }} — Kiali OIDC secret in istio-system

resources:
  - ../../../../../kustomize/base/kiali
