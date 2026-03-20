apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Auto-generated from cluster.yaml — do not edit
# Cluster: {{ (ds "ctx").computed.name }} — Gateway API resources

resources:
  - gateway.yaml
  - http-redirect.yaml
  - reference-grant.yaml
{{- if (ds "ctx").computed.isIstioMesh }}
{{- range (ds "routes").routes }}
  - {{ .filename }}
{{- end }}
  - ext-authz-policy.yaml
{{- end }}
