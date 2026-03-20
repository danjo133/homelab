{{- $ctx := (ds "ctx") -}}
{{- $portalPrefix := $ctx.config.portalPrefix -}}
# kube-prometheus-stack — {{ $ctx.computed.name }} cluster overrides
grafana:
  ingress:
{{- if $ctx.computed.isIstioMesh }}
    enabled: false  # Uses Gateway API HTTPRoute
{{- end }}
    annotations:
      {{ $portalPrefix }}/name: "Grafana"
      {{ $portalPrefix }}/description: "Dashboards and observability"
      {{ $portalPrefix }}/icon: "\U0001F4CA"
      {{ $portalPrefix }}/category: "Monitoring"
      {{ $portalPrefix }}/order: "10"
    hosts:
      - grafana.{{ $ctx.computed.domain }}
    tls:
      - secretName: wildcard-{{ $ctx.computed.domainSlug }}-tls
        hosts:
          - grafana.{{ $ctx.computed.domain }}
  grafana.ini:
    server:
      root_url: "https://grafana.{{ $ctx.computed.domain }}"
    auth.generic_oauth:
      auth_url: "https://auth.{{ $ctx.computed.domain }}/realms/broker/protocol/openid-connect/auth"
      token_url: "https://auth.{{ $ctx.computed.domain }}/realms/broker/protocol/openid-connect/token"
      api_url: "https://auth.{{ $ctx.computed.domain }}/realms/broker/protocol/openid-connect/userinfo"
