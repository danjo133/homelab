# Auto-generated from cluster.yaml — do not edit
# Cluster: {{ (ds "ctx").computed.name }} — Gateway for *.{{ (ds "ctx").computed.domain }}
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: main-gateway
  namespace: {{ (ds "ctx").computed.gatewayNs }}
  annotations:
    external-dns.alpha.kubernetes.io/hostname: "*.{{ (ds "ctx").computed.domain }}"
spec:
  gatewayClassName: {{ (ds "ctx").computed.gatewayClass }}
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      hostname: "*.{{ (ds "ctx").computed.domain }}"
      allowedRoutes:
        namespaces:
          from: All
    - name: https
      protocol: HTTPS
      port: 443
      hostname: "*.{{ (ds "ctx").computed.domain }}"
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: wildcard-{{ (ds "ctx").computed.domainSlug }}-tls
            namespace: cert-manager
      allowedRoutes:
        namespaces:
          from: All
