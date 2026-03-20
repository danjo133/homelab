{{- $ctx := (ds "ctx") -}}
# {{ $ctx.computed.name }} cluster teleport-kube-agent overrides
proxyAddr: "teleport.{{ $ctx.config.supportDomain }}:3080"
kubeClusterName: "{{ $ctx.computed.name }}"

labels:
  env: homelab
  cluster: {{ $ctx.computed.name }}

apps:
  - name: "grafana-{{ $ctx.computed.name }}"
    uri: "http://grafana.monitoring.svc.cluster.local:3000"
    labels:
      env: homelab
      cluster: {{ $ctx.computed.name }}
  - name: "argocd-{{ $ctx.computed.name }}"
    uri: "https://argocd-server.argocd.svc.cluster.local:443"
    insecure_skip_verify: true
    labels:
      env: homelab
      cluster: {{ $ctx.computed.name }}
  - name: "headlamp-{{ $ctx.computed.name }}"
    uri: "http://headlamp.headlamp.svc.cluster.local:80"
    labels:
      env: homelab
      cluster: {{ $ctx.computed.name }}
