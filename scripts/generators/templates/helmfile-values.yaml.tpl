{{- $ctx := (ds "ctx") -}}
# Auto-generated from cluster.yaml — do not edit
# Cluster: {{ $ctx.computed.name }}
clusterName: {{ (ds "ctx").computed.name }}
clusterDomain: {{ (ds "ctx").computed.domain }}
domainSlug: {{ (ds "ctx").computed.domainSlug }}
k8sServiceHost: {{ (ds "ctx").computed.name }}-master.{{ (ds "ctx").computed.domain }}
lbPoolCidr: "{{ (ds "ctx").cluster.loadbalancer.cidr }}"
vaultAuthMount: {{ (ds "ctx").cluster.vault.auth_mount }}
vaultNamespace: {{ (ds "ctx").cluster.vault.namespace }}
bgpAsn: {{ (ds "ctx").cluster.bgp.asn }}
{{- if (ds "ctx").computed.oidcEnabled }}

# OIDC configuration
oidcEnabled: true
oidcIssuerUrl: "{{ (ds "ctx").computed.oidcIssuerUrl }}"
oidcClientId: "{{ (ds "ctx").cluster.oidc.client_id }}"
{{- end }}
