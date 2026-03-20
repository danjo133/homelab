apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Auto-generated from cluster.yaml — do not edit
# Cluster: {{ (ds "ctx").computed.name }} — Apps discovery (repo-creds, Harbor pull/push secrets)

resources:
  - namespace.yaml
  - gitlab-scm-token.yaml
  - gitlab-ssh-known-hosts.yaml
  - argocd-repo-creds-apps.yaml
  - harbor-image-updater-secret.yaml
  - harbor-pull-secret-apps.yaml
