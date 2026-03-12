{{/*
Compute memory request as half of the limit.
Handles Mi and Gi suffixes.
*/}}
{{- define "generic-app.halfMemory" -}}
{{- $mem := .Values.memory | toString -}}
{{- if hasSuffix "Gi" $mem -}}
  {{- $val := trimSuffix "Gi" $mem | float64 -}}
  {{- $half := divf $val 2.0 -}}
  {{- if eq (mod (mulf $half 1024.0 | int) 1024) 0 -}}
    {{- printf "%.0fGi" $half -}}
  {{- else -}}
    {{- printf "%.0fMi" (mulf $half 1024.0) -}}
  {{- end -}}
{{- else if hasSuffix "Mi" $mem -}}
  {{- $val := trimSuffix "Mi" $mem | int -}}
  {{- printf "%dMi" (div $val 2) -}}
{{- else -}}
  {{- $mem -}}
{{- end -}}
{{- end -}}
