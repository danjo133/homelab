{{- $ctx := (ds "ctx") -}}
{{- $domain := $ctx.computed.domain -}}
{{- $gatewayNs := $ctx.computed.gatewayNs -}}
{{- $portalPrefix := $ctx.config.portalPrefix -}}
{{- range $i, $route := (ds "routes").routes -}}
{{- if gt $i 0 }}
---
{{ end -}}
# Auto-generated from cluster.yaml — do not edit
# Cluster: {{ $ctx.computed.name }} — {{ $route.name | strings.Title }} HTTPRoute for Gateway API ingress
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ $route.name }}
  namespace: {{ $route.namespace }}
{{- if has $route "portal" }}
  annotations:
    {{ $portalPrefix }}/name: "{{ $route.portal.name }}"
    {{ $portalPrefix }}/description: "{{ $route.portal.description }}"
    {{ $portalPrefix }}/icon: "{{ $route.portal.icon }}"
    {{ $portalPrefix }}/category: "{{ $route.portal.category }}"
    {{ $portalPrefix }}/order: "{{ $route.portal.order }}"
{{- end }}
spec:
  parentRefs:
    - name: main-gateway
      namespace: {{ $gatewayNs }}
  hostnames:
    - "{{ $route.hostname }}.{{ $domain }}"
  rules:
{{- if has $route "extraRules" }}
{{- range $route.extraRules }}
    - matches:
        - path:
            type: PathPrefix
            value: {{ .pathPrefix }}
      backendRefs:
        - name: {{ .serviceName }}
          port: {{ .servicePort }}
{{- end }}
{{- end }}
    - matches:
        - path:
            type: PathPrefix
            value: {{ if has $route "pathPrefix" }}{{ $route.pathPrefix }}{{ else }}/{{ end }}
      backendRefs:
        - name: {{ $route.serviceName }}
          port: {{ $route.servicePort }}
{{ end -}}
