# Auto-generated from cluster.yaml — do not edit
# Cluster: {{ (ds "ctx").computed.name }} — Gateway deployment overrides
apiVersion: v1
kind: ConfigMap
metadata:
  name: main-gateway-params
  namespace: {{ (ds "ctx").computed.gatewayNs }}
data:
  deployment: |
    spec:
      template:
        spec:
          containers:
          - name: istio-proxy
            startupProbe:
              failureThreshold: 120
