{{- $ctx := (ds "ctx") -}}
# {{ $ctx.computed.name }} cluster trivy overrides
image:
  registry: {{ $ctx.config.harborRegistry }}
  repository: docker.io/aquasec/trivy-operator

trivy:
  image:
    registry: {{ $ctx.config.harborRegistry }}
    repository: docker.io/aquasec/trivy
  dbRegistry: {{ $ctx.config.harborRegistry }}
  dbRepository: docker.io/aquasec/trivy-db
  javaDbRegistry: {{ $ctx.config.harborRegistry }}
  javaDbRepository: docker.io/aquasec/trivy-java-db
