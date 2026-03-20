{{- $ctx := (ds "ctx") -}}
{{- $portalPrefix := $ctx.config.portalPrefix -}}
# Longhorn — {{ $ctx.computed.name }} cluster overrides
ingress:
{{- if $ctx.computed.isIstioMesh }}
  enabled: false  # Uses Gateway API HTTPRoute
{{- end }}
  host: longhorn.{{ $ctx.computed.domain }}
  tls: true
  tlsSecret: wildcard-{{ $ctx.computed.domainSlug }}-tls
{{- if not $ctx.computed.isIstioMesh }}
  annotations:
    {{ $portalPrefix }}/name: "Longhorn"
    {{ $portalPrefix }}/description: "Distributed block storage"
    {{ $portalPrefix }}/icon: "\U0001F4BE"
    {{ $portalPrefix }}/category: "Platform"
    {{ $portalPrefix }}/order: "30"
{{- end }}
