# Auto-generated from cluster.yaml — do not edit
# Cluster: {{ (ds "ctx").computed.name }} — HTTP to HTTPS redirect
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: http-to-https-redirect
  namespace: {{ (ds "ctx").computed.gatewayNs }}
spec:
  parentRefs:
    - name: main-gateway
      namespace: {{ (ds "ctx").computed.gatewayNs }}
      sectionName: http
  hostnames:
    - "*.{{ (ds "ctx").computed.domain }}"
  rules:
    - filters:
        - type: RequestRedirect
          requestRedirect:
            scheme: https
            statusCode: 301
