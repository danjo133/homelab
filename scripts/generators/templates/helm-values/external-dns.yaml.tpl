{{- $ctx := (ds "ctx") -}}
# ExternalDNS — {{ $ctx.computed.name }} cluster overrides
txtOwnerId: "k8s-cluster-{{ $ctx.computed.name }}"

domainFilters:
  - {{ $ctx.computed.rootDomain }}
{{- if $ctx.computed.isIstioMesh }}

sources:
  - service
  - ingress
  - gateway-httproute
{{- end }}
