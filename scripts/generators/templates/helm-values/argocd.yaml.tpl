{{- $ctx := (ds "ctx") -}}
# ArgoCD — {{ $ctx.computed.name }} cluster overrides
# Auto-generated from cluster.yaml — do not edit
server:
  ingress:
    hostname: argocd.{{ $ctx.computed.domain }}
{{- if $ctx.computed.isIstioMesh }}
    enabled: false  # Uses Gateway API HTTPRoute
{{- end }}

configs:
  cm:
    url: "https://argocd.{{ $ctx.computed.domain }}"
    oidc.config: |
      name: Keycloak
      issuer: https://auth.{{ $ctx.computed.domain }}/realms/broker
      clientID: argocd
      clientSecret: $argocd-oidc-secret:client-secret
      requestedScopes:
        - openid
        - profile
        - email
        - groups
