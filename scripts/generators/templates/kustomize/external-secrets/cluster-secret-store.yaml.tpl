# Auto-generated from cluster.yaml — do not edit
# Cluster: {{ (ds "ctx").computed.name }} — ClusterSecretStore with per-cluster Vault namespace
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: vault
spec:
  provider:
    vault:
      server: "https://vault.{{ (ds "ctx").config.supportDomain }}"
      path: "secret"
      version: "v2"
      namespace: "{{ (ds "ctx").computed.vaultNamespace }}"
      auth:
        kubernetes:
          mountPath: "{{ (ds "ctx").computed.vaultAuthMount }}"
          role: "external-secrets"
          serviceAccountRef:
            name: "external-secrets"
            namespace: "external-secrets"
