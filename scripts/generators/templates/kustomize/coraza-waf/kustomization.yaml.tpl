apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Auto-generated from cluster.yaml — do not edit
# Cluster: {{ (ds "ctx").computed.name }} — Coraza WAF WasmPlugin

resources:
  - ../../../../../kustomize/base/coraza-waf

patches:
  - target:
      kind: WasmPlugin
      name: coraza-waf
    patch: |
      - op: replace
        path: /spec/url
        value: "oci://{{ (ds "ctx").config.harborRegistry }}/ghcr.io/corazawaf/coraza-proxy-wasm"
