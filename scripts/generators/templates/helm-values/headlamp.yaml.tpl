{{- $ctx := (ds "ctx") -}}
{{- $portalPrefix := $ctx.config.portalPrefix -}}
{{- if $ctx.computed.isIstioMesh -}}
# Headlamp — {{ $ctx.computed.name }} cluster overrides (no ingress, uses HTTPRoute)
ingress:
  enabled: false
{{- else -}}
# Headlamp — {{ $ctx.computed.name }} cluster overrides
ingress:
  enabled: true
  ingressClassName: nginx
  annotations:
    {{ $portalPrefix }}/name: "Headlamp"
    {{ $portalPrefix }}/description: "Kubernetes dashboard"
    {{ $portalPrefix }}/icon: "\U0001F4BB"
    {{ $portalPrefix }}/category: "Platform"
    {{ $portalPrefix }}/order: "20"
  hosts:
    - host: headlamp.{{ $ctx.computed.domain }}
      paths:
        - path: /
          type: ImplementationSpecific
  tls:
    - secretName: wildcard-{{ $ctx.computed.domainSlug }}-tls
      hosts:
        - headlamp.{{ $ctx.computed.domain }}
{{- end }}
