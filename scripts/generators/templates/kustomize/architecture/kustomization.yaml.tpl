apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Auto-generated from cluster.yaml — do not edit
# Cluster: {{ (ds "ctx").computed.name }} — Architecture diagram viewer

resources:
  - ../../../../../kustomize/base/architecture

patches:
  - target:
      kind: Deployment
      name: architecture
    patch: |
      - op: replace
        path: /spec/template/spec/containers/0/image
        value: {{ (ds "ctx").config.harborRegistry }}/apps/architecture:latest
{{- if (ds "ctx").computed.isIstioMesh }}
  - patch: |
      apiVersion: networking.k8s.io/v1
      kind: Ingress
      metadata:
        name: architecture
        namespace: kube-public
      $patch: delete
{{- else }}
  - target:
      kind: Ingress
      name: architecture
    patch: |
      - op: replace
        path: /spec/tls/0/hosts/0
        value: architecture.{{ (ds "ctx").computed.domain }}
      - op: replace
        path: /spec/rules/0/host
        value: architecture.{{ (ds "ctx").computed.domain }}
      - op: replace
        path: /metadata/annotations/nginx.ingress.kubernetes.io~1auth-signin
        value: "https://oauth2-proxy.{{ (ds "ctx").computed.domain }}/oauth2/start?rd=$scheme://$host$escaped_request_uri"
{{- end }}
