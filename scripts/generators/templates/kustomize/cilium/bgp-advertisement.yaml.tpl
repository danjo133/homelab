{{- $ctx := (ds "ctx") -}}
# Auto-generated from cluster.yaml — do not edit
# Cluster: {{ $ctx.computed.name }}
apiVersion: cilium.io/v2
kind: CiliumBGPAdvertisement
metadata:
  name: {{ (ds "ctx").computed.name }}-advertise-lb
  labels:
    advertise: "bgp"
spec:
  advertisements:
    - advertisementType: Service
      service:
        addresses:
          - LoadBalancerIP
      selector:
        matchExpressions:
          - key: never-used-key
            operator: NotIn
            values: ["never-used-value"]
