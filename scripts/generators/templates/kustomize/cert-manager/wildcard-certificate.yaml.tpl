# Auto-generated from cluster.yaml — do not edit
# Cluster: {{ (ds "ctx").computed.name }} — Wildcard certificate for *.{{ (ds "ctx").computed.domain }}
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-{{ (ds "ctx").computed.domainSlug }}
  namespace: cert-manager
spec:
  secretName: wildcard-{{ (ds "ctx").computed.domainSlug }}-tls
  duration: 2160h
  renewBefore: 360h
  commonName: "*.{{ (ds "ctx").computed.domain }}"
  dnsNames:
    - "*.{{ (ds "ctx").computed.domain }}"
    - "{{ (ds "ctx").computed.domain }}"
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  privateKey:
    algorithm: ECDSA
    size: 256
