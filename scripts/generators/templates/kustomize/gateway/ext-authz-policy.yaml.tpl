# Auto-generated from cluster.yaml — do not edit
# Cluster: {{ (ds "ctx").computed.name }} — ext_authz via OAuth2-Proxy for protected services
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: oauth2-proxy-auth
  namespace: {{ (ds "ctx").computed.gatewayNs }}
spec:
  targetRef:
    kind: Gateway
    group: gateway.networking.k8s.io
    name: main-gateway
  action: CUSTOM
  provider:
    name: oauth2-proxy
  rules:
    - to:
        - operation:
            hosts:
              - "setup.{{ (ds "ctx").computed.domain }}"
              - "hubble.{{ (ds "ctx").computed.domain }}"
