{{- $ctx := (ds "ctx") -}}
# Auto-generated — do not edit
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
spec:
  project: bootstrap
  sources:
    - repoURL: {{ $ctx.config.gitRepoUrl }}
      targetRevision: {{ $ctx.config.targetRevision }}
      ref: values
    - repoURL: {{ $ctx.config.gitRepoUrl }}
      targetRevision: {{ $ctx.config.targetRevision }}
      path: iac/argocd/chart
      helm:
        valueFiles:
          - $values/iac/argocd/chart/values.yaml
          - $values/iac/argocd/chart/values-{{ $ctx.computed.name }}.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
