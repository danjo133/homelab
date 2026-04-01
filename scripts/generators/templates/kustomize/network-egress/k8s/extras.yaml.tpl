{{- $ctx := (ds "ctx") -}}
{{- $gatewayIp := $ctx.config.gatewayIp -}}
# nginx ingress: accept external client traffic
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-external-ingress
  namespace: ingress-nginx
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress:
    - {}
---
# CoreDNS: upstream DNS to router
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: coredns-upstream
  namespace: kube-system
spec:
  podSelector:
    matchLabels:
      k8s-app: kube-dns
  policyTypes:
    - Egress
  egress:
    - to:
        - ipBlock:
            cidr: {{ $gatewayIp }}/32
      ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
{{- range (ds "netpol").webhookNamespaces }}
---
# {{ .namespace }}: API server → admission webhook
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-apiserver-webhook
  namespace: {{ .namespace }}
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress:
    - from:
        - ipBlock:
            cidr: {{ $ctx.config.podCidr }}
      ports:
        - port: {{ .port }}
          protocol: TCP
{{- end }}
{{- range (ds "netpol").internetNamespaces }}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-internet
  namespace: {{ . }}
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except:
              - 10.0.0.0/8
              - 172.16.0.0/12
              - 192.168.0.0/16
{{- end }}
