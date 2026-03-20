{{- $ctx := (ds "ctx") -}}
# Auto-generated from cluster.yaml — do not edit
# Cluster: {{ $ctx.computed.name }}

CLUSTER_NAME := {{ (ds "ctx").computed.name }}
CLUSTER_DOMAIN := {{ (ds "ctx").computed.domain }}
CLUSTER_MASTER_IP := {{ (ds "ctx").cluster.master.ip }}
CLUSTER_MASTER_MAC := {{ (ds "ctx").cluster.master.mac }}
CLUSTER_MASTER_MEMORY := {{ (ds "ctx").cluster.master.memory }}
CLUSTER_MASTER_CPUS := {{ (ds "ctx").cluster.master.cpus }}
CLUSTER_CNI := {{ (ds "ctx").computed.cni }}
CLUSTER_HELMFILE_ENV := {{ (ds "ctx").computed.helmfileEnv }}
CLUSTER_LB_CIDR := {{ (ds "ctx").cluster.loadbalancer.cidr }}
CLUSTER_VAULT_AUTH_MOUNT := {{ (ds "ctx").cluster.vault.auth_mount }}
CLUSTER_VAULT_NAMESPACE := {{ (ds "ctx").cluster.vault.namespace }}
CLUSTER_BGP_ASN := {{ (ds "ctx").cluster.bgp.asn }}
{{- range $i, $w := (ds "ctx").cluster.workers }}
{{- $n := add $i 1 }}

CLUSTER_WORKER_{{ $n }}_NAME := {{ $w.name }}
CLUSTER_WORKER_{{ $n }}_IP := {{ $w.ip }}
CLUSTER_WORKER_{{ $n }}_MAC := {{ $w.mac }}
CLUSTER_WORKER_{{ $n }}_MEMORY := {{ $w.memory }}
CLUSTER_WORKER_{{ $n }}_CPUS := {{ $w.cpus }}
{{- end }}

CLUSTER_WORKER_COUNT := {{ len (ds "ctx").cluster.workers }}
CLUSTER_WORKER_VMS :={{ range $i, $w := (ds "ctx").cluster.workers }} {{ (ds "ctx").computed.name }}-{{ $w.name }}{{ end }}
CLUSTER_ALL_VMS := {{ (ds "ctx").computed.name }}-master{{ range $i, $w := (ds "ctx").cluster.workers }} {{ (ds "ctx").computed.name }}-{{ $w.name }}{{ end }}
