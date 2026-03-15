{{/*
Domain slug: clusterDomain with dots replaced by dashes.
Used for TLS secret names (e.g., wildcard-kss-example-com-tls).
*/}}
{{- define "root-app.domainSlug" -}}
{{- .Values.clusterDomain | replace "." "-" -}}
{{- end -}}

{{/*
Master FQDN: explicit value or derived from clusterName + clusterDomain.
*/}}
{{- define "root-app.masterFqdn" -}}
{{- if .Values.master.fqdn -}}
{{- .Values.master.fqdn -}}
{{- else -}}
{{- printf "%s-master.%s" .Values.clusterName .Values.clusterDomain -}}
{{- end -}}
{{- end -}}

{{/*
Path to a per-cluster kustomize overlay.
Usage: {{ include "root-app.overlayPath" (dict "root" . "overlay" "keycloak") }}
*/}}
{{- define "root-app.overlayPath" -}}
{{- printf "iac/argocd/clusters/%s/kustomize/%s" .root.Values.clusterName .overlay -}}
{{- end -}}

{{/*
Condition helpers for cluster type.
*/}}
{{- define "root-app.isCilium" -}}
{{- eq .Values.cni "cilium" -}}
{{- end -}}

{{- define "root-app.isIstioMesh" -}}
{{- eq .Values.helmfileEnv "istio-mesh" -}}
{{- end -}}

{{- define "root-app.hasGatewayAPI" -}}
{{- or (eq .Values.helmfileEnv "gateway-bgp") (eq .Values.helmfileEnv "istio-mesh") -}}
{{- end -}}

{{/*
Standard sync policy used by most Applications.
*/}}
{{- define "root-app.syncPolicy" -}}
syncPolicy:
  automated:
    prune: true
    selfHeal: true
  syncOptions:
    - CreateNamespace=true
{{- end -}}

{{/*
GitLab apps SSH wildcard URL for AppProject sourceRepos.
*/}}
{{- define "root-app.appsRepoPattern" -}}
{{- printf "%s/apps/*" .Values.gitlabSshUrl -}}
{{- end -}}
