# Auto-generated from cluster.yaml — do not edit
# Cluster: {{ (ds "ctx").computed.name }} — Allow Gateway to reference cert-manager secrets
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-gateway-secret-reference
  namespace: cert-manager
spec:
  from:
    - group: gateway.networking.k8s.io
      kind: Gateway
      namespace: {{ (ds "ctx").computed.gatewayNs }}
  to:
    - group: ""
      kind: Secret
      name: wildcard-{{ (ds "ctx").computed.domainSlug }}-tls
