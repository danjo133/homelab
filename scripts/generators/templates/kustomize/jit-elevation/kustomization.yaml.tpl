apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Auto-generated from cluster.yaml — do not edit
# Cluster: {{ (ds "ctx").computed.name }} — JIT Elevation with per-cluster hostname

resources:
  - ../../../../../kustomize/base/jit-elevation

patches:
  - target:
      kind: ConfigMap
      name: jit-config
    patch: |
      - op: replace
        path: /data/KEYCLOAK_URL
        value: "https://auth.{{ (ds "ctx").computed.domain }}"
  - target:
      kind: Deployment
      name: jit-elevation
    patch: |
      - op: replace
        path: /spec/template/spec/containers/0/image
        value: {{ (ds "ctx").config.harborRegistry }}/apps/jit-elevation:latest
{{- if (ds "ctx").computed.isIstioMesh }}
  - patch: |
      apiVersion: networking.k8s.io/v1
      kind: Ingress
      metadata:
        name: jit-elevation
        namespace: identity
      $patch: delete
{{- else }}
  - target:
      kind: Ingress
      name: jit-elevation
    patch: |
      - op: replace
        path: /spec/tls/0/hosts/0
        value: jit.{{ (ds "ctx").computed.domain }}
      - op: replace
        path: /spec/rules/0/host
        value: jit.{{ (ds "ctx").computed.domain }}
{{- end }}
