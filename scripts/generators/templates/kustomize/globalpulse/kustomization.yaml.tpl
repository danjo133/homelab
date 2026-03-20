apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Auto-generated from cluster.yaml — do not edit
# Cluster: {{ (ds "ctx").computed.name }} — GlobalPulse world monitor

resources:
  - ../../../../../kustomize/base/globalpulse

patches:
  - target:
      kind: Deployment
      name: globalpulse
    patch: |
      - op: replace
        path: /spec/template/spec/containers/0/image
        value: {{ (ds "ctx").config.harborRegistry }}/library/globalpulse:latest
{{- if (ds "ctx").computed.isIstioMesh }}
  - patch: |
      apiVersion: networking.k8s.io/v1
      kind: Ingress
      metadata:
        name: globalpulse
        namespace: globalpulse
      $patch: delete
{{- else }}
  - target:
      kind: Ingress
      name: globalpulse
    patch: |
      - op: replace
        path: /spec/tls/0/hosts/0
        value: world.{{ (ds "ctx").computed.domain }}
      - op: replace
        path: /spec/rules/0/host
        value: world.{{ (ds "ctx").computed.domain }}
      - op: replace
        path: /metadata/annotations/nginx.ingress.kubernetes.io~1auth-signin
        value: "https://oauth2-proxy.{{ (ds "ctx").computed.domain }}/oauth2/start?rd=$scheme://$host$escaped_request_uri"
{{- end }}
