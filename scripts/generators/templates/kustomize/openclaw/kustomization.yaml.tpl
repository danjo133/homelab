{{- $ctx := (ds "ctx") -}}
{{- $domain := $ctx.computed.domain -}}
{{- $harborRegistry := $ctx.config.harborRegistry -}}
{{- $ollamaUrl := $ctx.config.ollamaUrl -}}
{{- $openclawModel := $ctx.config.openclawModel -}}
{{- $modelId := $openclawModel | strings.TrimPrefix "ollama/" -}}
{{- $signalAccount := $ctx.config.signalAccount -}}
{{- $signalAllowFrom := $ctx.config.signalAllowFrom -}}
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Auto-generated from cluster.yaml — do not edit
# Cluster: {{ $ctx.computed.name }} — OpenClaw with per-cluster Ollama URL

resources:
  - ../../../../../kustomize/base/openclaw

patches:
  - target:
      kind: Deployment
      name: openclaw
    patch: |
      - op: replace
        path: /spec/template/spec/initContainers/0/image
        value: "{{ $harborRegistry }}/apps/openclaw:latest"
      - op: replace
        path: /spec/template/spec/containers/0/image
        value: "{{ $harborRegistry }}/apps/openclaw:latest"
      - op: replace
        path: /spec/template/spec/containers/0/env/1/value
        value: "{{ $ollamaUrl }}"
  - target:
      kind: ConfigMap
      name: openclaw-config
    patch: |
      - op: replace
        path: /data/openclaw.json
        value: |
          {
            "gateway": {
              "mode": "local",
              "bind": "lan",
              "port": 18789,
              "auth": {
                "mode": "token"
              },
              "controlUi": {
                "enabled": true,
                "allowedOrigins": ["https://claw.{{ $domain }}"]
              }
            },
            "agents": {
              "defaults": {
                "model": {
                  "primary": "{{ $openclawModel }}"
                }
              }
            },
            "models": {
              "providers": {
                "ollama": {
                  "baseUrl": "{{ $ollamaUrl }}",
                  "apiKey": "ollama",
                  "api": "ollama",
                  "models": [
                    {
                      "id": "{{ $modelId }}",
                      "name": "{{ $modelId }}",
                      "reasoning": true,
                      "input": ["text", "image"],
                      "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
                      "contextWindow": 262144,
                      "maxTokens": 32768
                    }
                  ]
                }
              }
            },
            "channels": {
              "signal": {
                "enabled": {{ if $signalAccount }}true{{ else }}false{{ end }},
                "account": "{{ $signalAccount }}",
                "cliPath": "signal-cli",
                "autoStart": true,
                "dmPolicy": "pairing",
                "allowFrom": [{{ $signalAllowFrom }}]
              }
            }
          }
