{{- $ctx := (ds "ctx") -}}
{{- if $ctx.computed.isIstioMesh -}}
# Kiali — {{ $ctx.computed.name }} cluster values
auth:
  strategy: openid
  openid:
    client_id: kiali
    issuer_uri: "https://auth.{{ $ctx.computed.domain }}/realms/broker"
    scopes:
      - openid
      - profile
      - email
      - groups
    username_claim: preferred_username
    disable_rbac: true

external_services:
  prometheus:
    url: "http://kube-prometheus-stack-prometheus.monitoring:9090"
  grafana:
    enabled: true
    in_cluster_url: "http://kube-prometheus-stack-grafana.monitoring:80"
    url: "https://grafana.{{ $ctx.computed.domain }}"
  tracing:
    enabled: false

deployment:
  replicas: 1
  resources:
    requests:
      cpu: 10m
      memory: 64Mi
    limits:
      memory: 256Mi

server:
  port: 20001
  web_fqdn: kiali.{{ $ctx.computed.domain }}
  web_port: "443"
  web_root: /
  web_schema: https
{{- end }}
