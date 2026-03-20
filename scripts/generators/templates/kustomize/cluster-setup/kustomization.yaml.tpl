apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Auto-generated from cluster.yaml — do not edit
# Cluster: {{ (ds "ctx").computed.name }} — Cluster Setup with per-cluster config

resources:
  - ../../../../../kustomize/base/cluster-setup

patches:
  - target:
      kind: ConfigMap
      name: cluster-setup-config
    patch: |
      - op: replace
        path: /data/CLUSTER_NAME
        value: "{{ (ds "ctx").computed.name }}"
      - op: replace
        path: /data/CLUSTER_DOMAIN
        value: "{{ (ds "ctx").computed.domain }}"
      - op: replace
        path: /data/KEYCLOAK_URL
        value: "https://auth.{{ (ds "ctx").computed.domain }}"
      - op: replace
        path: /data/API_SERVER
        value: "https://{{ (ds "ctx").computed.name }}-master.{{ (ds "ctx").computed.domain }}:6443"
  - target:
      kind: Deployment
      name: cluster-setup
    patch: |
      - op: replace
        path: /spec/template/spec/containers/0/image
        value: {{ (ds "ctx").config.harborRegistry }}/apps/cluster-setup:latest
{{- if (ds "ctx").computed.isIstioMesh }}
  - patch: |
      apiVersion: networking.k8s.io/v1
      kind: Ingress
      metadata:
        name: cluster-setup
        namespace: identity
      $patch: delete
{{- else }}
  - target:
      kind: Ingress
      name: cluster-setup
    patch: |
      - op: replace
        path: /spec/tls/0/hosts/0
        value: setup.{{ (ds "ctx").computed.domain }}
      - op: replace
        path: /spec/rules/0/host
        value: setup.{{ (ds "ctx").computed.domain }}
      - op: replace
        path: /metadata/annotations/nginx.ingress.kubernetes.io~1auth-url
        value: "http://oauth2-proxy.oauth2-proxy.svc.cluster.local/oauth2/auth"
      - op: replace
        path: /metadata/annotations/nginx.ingress.kubernetes.io~1auth-signin
        value: "https://oauth2-proxy.{{ (ds "ctx").computed.domain }}/oauth2/start?rd=$scheme://$host$escaped_request_uri"
{{- end }}
