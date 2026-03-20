{{- $ctx := (ds "ctx") -}}
# SPIRE — {{ $ctx.computed.name }} cluster overrides
global:
  spire:
    trustDomain: {{ $ctx.computed.domain }}
    clusterName: {{ $ctx.computed.name }}

spire-server:
  oidcDiscoveryProvider:
    ingress:
{{- if $ctx.computed.isIstioMesh }}
      enabled: false
{{- else }}
      enabled: true
      className: nginx
      hosts:
        - spire-oidc.{{ $ctx.computed.domain }}
      annotations:
        cert-manager.io/cluster-issuer: letsencrypt-prod
      tls:
        - secretName: spire-oidc-tls
          hosts:
            - spire-oidc.{{ $ctx.computed.domain }}
{{- end }}
