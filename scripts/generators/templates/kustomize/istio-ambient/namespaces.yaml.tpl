# Auto-generated from cluster.yaml — do not edit
# Cluster: {{ (ds "ctx").computed.name }} — Istio ambient mesh namespace enrollment
{{- range (ds "namespaces").namespaces }}
---
apiVersion: v1
kind: Namespace
metadata:
  name: {{ . }}
  labels:
    istio.io/dataplane-mode: ambient
{{- end }}
