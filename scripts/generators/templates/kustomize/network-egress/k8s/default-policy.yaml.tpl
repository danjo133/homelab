{{- $ctx := (ds "ctx") -}}
{{- $nfsAllowedNetwork := $ctx.config.nfsAllowedNetwork -}}
{{- $gatewayIp := $ctx.config.gatewayIp -}}
{{- $serviceCidr := $ctx.config.serviceCidr -}}
{{- range $i, $ns := (ds "netpol").defaultPolicyNamespaces -}}
{{- if gt $i 0 }}
---
{{ end -}}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-policy
  namespace: {{ $ns }}
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # Allow from all cluster pods
    - from:
        - namespaceSelector: {}
    # Allow from nodes (kubelet probes, metrics)
    - from:
        - ipBlock:
            cidr: {{ $nfsAllowedNetwork }}
  egress:
    # DNS to kube-dns
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
    # Intra-cluster: all pods in all namespaces
    - to:
        - namespaceSelector: {}
    # Service CIDR — required for hostNetwork pods (Canal evaluates
    # NetworkPolicy before kube-proxy DNAT in the OUTPUT chain, so
    # ClusterIP destinations are not matched by namespaceSelector rules)
    - to:
        - ipBlock:
            cidr: {{ $serviceCidr }}
    # Node network (support VM, node services) except router
    - to:
        - ipBlock:
            cidr: {{ $nfsAllowedNetwork }}
            except:
              - {{ $gatewayIp }}/32
{{ end -}}
