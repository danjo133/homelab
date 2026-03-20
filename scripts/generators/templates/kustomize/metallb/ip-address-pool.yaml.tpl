{{- $ctx := (ds "ctx") -}}
# Auto-generated from cluster.yaml — do not edit
# Cluster: {{ $ctx.computed.name }}
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: {{ (ds "ctx").computed.name }}-pool
  namespace: metallb-system
spec:
  addresses:
    - {{ (ds "ctx").cluster.loadbalancer.cidr }}
