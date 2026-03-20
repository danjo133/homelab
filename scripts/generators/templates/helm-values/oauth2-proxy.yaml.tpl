{{- $ctx := (ds "ctx") -}}
# OAuth2-Proxy — {{ $ctx.computed.name }} cluster overrides
extraArgs:
  oidc-issuer-url: "https://auth.{{ $ctx.computed.domain }}/realms/broker"
  cookie-domain: ".{{ $ctx.computed.domain }}"
  whitelist-domain: ".{{ $ctx.computed.domain }}"
  redirect-url: "https://oauth2-proxy.{{ $ctx.computed.domain }}/oauth2/callback"

ingress:
{{- if $ctx.computed.isIstioMesh }}
  enabled: false  # Uses Gateway API HTTPRoute
{{- end }}
  hosts:
    - oauth2-proxy.{{ $ctx.computed.domain }}
  tls:
    - secretName: oauth2-proxy-tls
      hosts:
        - oauth2-proxy.{{ $ctx.computed.domain }}
