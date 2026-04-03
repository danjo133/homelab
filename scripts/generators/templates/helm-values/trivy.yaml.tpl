{{- $ctx := (ds "ctx") -}}
# {{ $ctx.computed.name }} cluster trivy overrides
image:
  registry: {{ $ctx.config.harborRegistry }}
  repository: ghcr.io/aquasecurity/trivy-operator

trivy:
  image:
    registry: {{ $ctx.config.harborRegistry }}
    repository: ghcr.io/aquasecurity/trivy
  dbRegistry: {{ $ctx.config.harborRegistry }}
  dbRepository: ghcr.io/aquasecurity/trivy-db
  javaDbRegistry: {{ $ctx.config.harborRegistry }}
  javaDbRepository: ghcr.io/aquasecurity/trivy-java-db
