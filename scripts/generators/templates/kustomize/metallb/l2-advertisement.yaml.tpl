{{- $ctx := (ds "ctx") -}}
# Auto-generated from cluster.yaml — do not edit
# Cluster: {{ $ctx.computed.name }}
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: {{ (ds "ctx").computed.name }}-l2-advert
  namespace: metallb-system
spec:
  ipAddressPools:
    - {{ (ds "ctx").computed.name }}-pool
