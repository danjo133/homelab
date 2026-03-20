{{- $ctx := (ds "ctx") -}}
{{- $supportVmIp := $ctx.config.supportVmIp -}}
{{- $gatewayIp := $ctx.config.gatewayIp -}}
{{- $ollamaIp := $ctx.config.ollamaIp -}}
{{- range $i, $policy := (ds "policies").policies -}}
{{- if gt $i 0 }}
---
{{ end -}}
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: {{ $policy.name }}
  namespace: {{ $policy.namespace }}
spec:
  description: {{ $policy.description | quote }}
{{- if has $policy "endpointSelector" }}
  endpointSelector:
    matchLabels:
{{- range $k, $v := $policy.endpointSelector.matchLabels }}
      {{ $k }}: {{ $v }}
{{- end }}
{{- else }}
  endpointSelector: {}
{{- end }}
  egress:
{{- range $policy.egress }}
{{- if has . "toCIDR" }}
    - toCIDR:
{{- if eq .toCIDR "SUPPORT_VM_IP" }}
        - "{{ $supportVmIp }}/32"
{{- else if eq .toCIDR "GATEWAY_IP" }}
        - "{{ $gatewayIp }}/32"
{{- else if eq .toCIDR "OLLAMA_IP" }}
        - "{{ $ollamaIp }}/32"
{{- end }}
{{- if has . "ports" }}
      toPorts:
        - ports:
{{- range .ports }}
            - port: {{ .port | quote }}
              protocol: {{ .protocol }}
{{- end }}
{{- end }}
{{- end }}
{{- if has . "internet" }}
    - toCIDRSet:
        - cidr: "0.0.0.0/0"
          except:
            - "10.0.0.0/8"
            - "172.16.0.0/12"
            - "192.168.0.0/16"
{{- if has . "ports" }}
      toPorts:
        - ports:
{{- range .ports }}
            - port: {{ .port | quote }}
              protocol: {{ .protocol }}
{{- end }}
{{- end }}
{{- end }}
{{- if has . "fqdns" }}
    - toFQDNs:
{{- range .fqdns }}
        - matchName: {{ . | quote }}
{{- end }}
{{- if has . "ports" }}
      toPorts:
        - ports:
{{- range .ports }}
            - port: {{ .port | quote }}
              protocol: {{ .protocol }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{ end -}}
