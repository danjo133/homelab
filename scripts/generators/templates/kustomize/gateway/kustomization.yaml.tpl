apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Auto-generated from cluster.yaml — do not edit
# Cluster: {{ (ds "ctx").computed.name }} — Gateway API resources

resources:
  - gateway.yaml
  - http-redirect.yaml
{{- if (ds "ctx").computed.isIstioMesh }}
  - reference-grant.yaml
  - httproutes.yaml
  - ext-authz-policy.yaml
{{- end }}
