{{- $ctx := (ds "ctx") -}}
# {{ $ctx.computed.name }} cluster argocd-image-updater overrides
config:
  registries:
    - name: Harbor
      api_url: https://{{ $ctx.config.harborRegistry }}
      prefix: {{ $ctx.config.harborRegistry }}
      credentials: pullsecret:argocd/harbor-image-updater-secret
      defaultns: library
      default: true
