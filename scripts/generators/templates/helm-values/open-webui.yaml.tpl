{{- $ctx := (ds "ctx") -}}
{{- if $ctx.computed.isIstioMesh -}}
ingress:
  enabled: false  # Uses Istio Gateway API HTTPRoute

sso:
  oidc:
    providerUrl: "https://auth.{{ $ctx.computed.domain }}/realms/broker/.well-known/openid-configuration"
{{- end -}}
