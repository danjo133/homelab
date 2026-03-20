{{- $ctx := (ds "ctx") -}}
# {{ $ctx.computed.name }} cluster ziti-router overrides
ctrl:
  endpoint: "{{ $ctx.config.zitiDomain }}:2029"
edge:
  advertisedHost: ziti-router.{{ $ctx.computed.domain }}
  advertisedPort: 443
