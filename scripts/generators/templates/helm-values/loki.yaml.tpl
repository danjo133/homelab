{{- $ctx := (ds "ctx") -}}
# Loki — {{ $ctx.computed.name }} cluster overrides
loki:
  storage:
    s3:
      endpoint: https://minio.{{ $ctx.config.supportDomain }}
      bucketnames: loki-{{ $ctx.computed.name }}
    bucketNames:
      chunks: loki-{{ $ctx.computed.name }}
      ruler: loki-{{ $ctx.computed.name }}
      admin: loki-{{ $ctx.computed.name }}
