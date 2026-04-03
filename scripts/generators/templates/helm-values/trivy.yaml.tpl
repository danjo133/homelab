{{- $ctx := (ds "ctx") -}}
# {{ $ctx.computed.name }} cluster trivy overrides
image:
  registry: {{ $ctx.config.harborRegistry }}
  repository: ghcr.io/aquasec/trivy-operator

trivy:
  image:
    registry: {{ $ctx.config.harborRegistry }}
    repository: ghcr.io/aquasec/trivy
  dbRegistry: {{ $ctx.config.harborRegistry }}
  dbRepository: ghcr.io/aquasec/trivy-db
  javaDbRegistry: {{ $ctx.config.harborRegistry }}
  javaDbRepository: ghcr.io/aquasec/trivy-java-db
