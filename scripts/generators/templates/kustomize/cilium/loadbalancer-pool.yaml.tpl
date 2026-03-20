{{- $ctx := (ds "ctx") -}}
# Auto-generated from cluster.yaml — do not edit
# Cluster: {{ $ctx.computed.name }}
apiVersion: cilium.io/v2
kind: CiliumLoadBalancerIPPool
metadata:
  name: {{ (ds "ctx").computed.name }}-pool
spec:
  allowFirstLastIPs: "No"
  blocks:
    - cidr: "{{ (ds "ctx").cluster.loadbalancer.cidr }}"
  serviceSelector:
    matchExpressions:
      - key: never-used-key
        operator: NotIn
        values: ["never-used-value"]
