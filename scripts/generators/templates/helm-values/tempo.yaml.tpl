{{- $ctx := (ds "ctx") -}}
# Tempo — {{ $ctx.computed.name }} cluster overrides
tempo:
  storage:
    trace:
      s3:
        endpoint: minio.{{ $ctx.config.supportDomain }}
        bucket: tempo-{{ $ctx.computed.name }}
