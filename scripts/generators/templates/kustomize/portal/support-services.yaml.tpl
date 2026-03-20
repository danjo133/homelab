# Auto-generated — support VM portal discovery entries
{{- $supportDomain := (ds "ctx").config.supportDomain }}
{{- $services := (ds "services").services }}
{{- range $services }}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: support-{{ .id }}
  namespace: kube-public
  annotations:
    external-dns.alpha.kubernetes.io/exclude: "true"
    portal.homelab/name: "{{ .name }}"
    portal.homelab/description: "{{ .description }}"
    portal.homelab/icon: "{{ .icon }}"
    portal.homelab/category: "{{ .category }}"
    portal.homelab/order: "{{ .order }}"
spec:
  rules:
    - host: {{ .subdomain }}.{{ $supportDomain }}
{{- end }}
