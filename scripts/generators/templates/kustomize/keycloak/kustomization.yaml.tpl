apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Auto-generated from cluster.yaml — do not edit
# Cluster: {{ (ds "ctx").computed.name }} — Keycloak broker with per-cluster hostname

resources:
  - ../../../../../kustomize/base/keycloak

patches:
  - target:
      kind: Keycloak
      name: broker-keycloak
    patch: |
      - op: replace
        path: /spec/hostname/hostname
        value: auth.{{ (ds "ctx").computed.domain }}
{{- if (ds "ctx").computed.isIstioMesh }}
  - patch: |
      apiVersion: networking.k8s.io/v1
      kind: Ingress
      metadata:
        name: broker-keycloak
        namespace: keycloak
      $patch: delete
{{- else }}
  - target:
      kind: Ingress
      name: broker-keycloak
    patch: |
      - op: replace
        path: /spec/tls/0/hosts/0
        value: auth.{{ (ds "ctx").computed.domain }}
      - op: replace
        path: /spec/rules/0/host
        value: auth.{{ (ds "ctx").computed.domain }}
{{- end }}
