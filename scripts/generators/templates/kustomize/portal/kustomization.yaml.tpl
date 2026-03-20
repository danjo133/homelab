apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Auto-generated from cluster.yaml — do not edit
# Cluster: {{ (ds "ctx").computed.name }} — Portal with per-cluster config

resources:
  - ../../../../../kustomize/base/portal
  - support-services.yaml

patches:
  - target:
      kind: ConfigMap
      name: portal-config
    patch: |
      - op: replace
        path: /data/CLUSTER_NAME
        value: "{{ (ds "ctx").computed.name }}"
      - op: replace
        path: /data/CLUSTER_DOMAIN
        value: "{{ (ds "ctx").computed.domain }}"
  - target:
      kind: Deployment
      name: portal
    patch: |
      - op: replace
        path: /spec/template/spec/containers/0/image
        value: {{ (ds "ctx").config.harborRegistry }}/apps/portal:latest
{{- if (ds "ctx").computed.isIstioMesh }}
  - patch: |
      apiVersion: networking.k8s.io/v1
      kind: Ingress
      metadata:
        name: portal
        namespace: kube-public
      $patch: delete
{{- else }}
  - target:
      kind: Ingress
      name: portal
    patch: |
      - op: replace
        path: /spec/tls/0/hosts/0
        value: portal.{{ (ds "ctx").computed.domain }}
      - op: replace
        path: /spec/rules/0/host
        value: portal.{{ (ds "ctx").computed.domain }}
      - op: replace
        path: /metadata/annotations/nginx.ingress.kubernetes.io~1auth-signin
        value: "https://oauth2-proxy.{{ (ds "ctx").computed.domain }}/oauth2/start?rd=$scheme://$host$escaped_request_uri"
{{- end }}
