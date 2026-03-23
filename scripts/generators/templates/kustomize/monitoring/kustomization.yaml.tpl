apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Auto-generated from cluster.yaml — do not edit
# Cluster: {{ (ds "ctx").computed.name }} — Monitoring ExternalSecrets

resources:
  - ../../../../../kustomize/base/monitoring

patches:
  # Per-cluster Vault path for Loki MinIO credentials
  - target:
      kind: ExternalSecret
      name: loki-minio-secret
    patch: |
      - op: replace
        path: /spec/data/0/remoteRef/key
        value: minio/loki-{{ (ds "ctx").computed.name }}
      - op: replace
        path: /spec/data/1/remoteRef/key
        value: minio/loki-{{ (ds "ctx").computed.name }}
  # Per-cluster Vault path for Tempo MinIO credentials
  - target:
      kind: ExternalSecret
      name: tempo-minio-secret
    patch: |
      - op: replace
        path: /spec/data/0/remoteRef/key
        value: minio/tempo-{{ (ds "ctx").computed.name }}
      - op: replace
        path: /spec/data/1/remoteRef/key
        value: minio/tempo-{{ (ds "ctx").computed.name }}
