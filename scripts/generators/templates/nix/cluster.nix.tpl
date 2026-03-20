{{- $ctx := (ds "ctx") -}}
# Auto-generated from cluster.yaml — do not edit
# Cluster: {{ $ctx.computed.name }}
{ config, lib, ... }:
{
  imports = [
    ./k8s-common/cluster-options.nix
  ];

  kss.cni = "{{ (ds "ctx").computed.cni }}";

  kss.cluster = {
    name = "{{ (ds "ctx").computed.name }}";
    domain = "{{ (ds "ctx").computed.domain }}";
    masterIp = "{{ (ds "ctx").cluster.master.ip }}";
    masterHostname = "{{ (ds "ctx").computed.name }}-master";
    vaultAuthMount = "{{ (ds "ctx").cluster.vault.auth_mount }}";
    vaultNamespace = "{{ (ds "ctx").cluster.vault.namespace }}";
    gatewayIp = "{{ (ds "ctx").config.gatewayIp }}";
    managementCidr = "{{ (ds "ctx").config.managementCidr }}";
    podCidr = "{{ (ds "ctx").config.podCidr }}";
    ollamaIp = "{{ (ds "ctx").config.ollamaIp }}";
  };
{{- if (ds "ctx").computed.oidcEnabled }}

  kss.cluster.oidc = {
    enabled = true;
    issuerUrl = "{{ (ds "ctx").cluster.oidc.issuer_url }}";
    clientId = "{{ (ds "ctx").cluster.oidc.client_id }}";
  };
{{- end }}
}
