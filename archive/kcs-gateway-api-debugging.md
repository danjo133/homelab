# KCS Cluster: Gateway API Debugging Notes

Date: 2026-02-09

## Cluster Setup

- **Cluster**: kcs (keep it complex stupid)
- **Domain**: mesh-k8s.example.com
- **Helmfile env**: gateway-bgp
- **CNI**: Cilium 1.19.0
- **Profile**: profile-gateway-bgp.yaml
- **BGP**: ASN 64513, peer 10.69.50.1 (router), session established
- **Gateway VIP**: 10.69.50.209 (from CiliumLoadBalancerIPPool kcs-pool, CIDR 10.69.50.208/28)

## What Works

- Cilium CNI: pod networking, VXLAN tunnel mode
- BGP: session established with router, VIP 10.69.50.209/32 advertised (1 route)
- kube-proxy replacement via Cilium BPF
- Gateway resource: Accepted + Programmed, GatewayClass cilium
- Gateway service: type LoadBalancer with external IP 10.69.50.209
- CiliumEnvoyConfig: created by operator, has correct backend (demo:80) and listener config
- Envoy DaemonSet: all 4 pods running, xDS streams connected, listener bound (no permission errors)
- HTTPRoute: demo.mesh-k8s.example.com attached to gateway
- Demo app: reachable via ClusterIP (curl demo.demo.svc:80 returns HTTP 200)
- ExternalDNS: creating records in Cloudflare for *.mesh-k8s.example.com and demo.mesh-k8s.example.com

## What Does NOT Work

- **External traffic to VIP 10.69.50.209 times out** (curl hangs, HTTP 000)
- Traffic from inside the cluster to the VIP also fails (same issue)

## Root Cause Analysis

### BPF Service Map State

```
cilium bpf lb list | grep 50.209:
10.69.50.209:80/TCP   0.0.0.0:0 (45) [LoadBalancer, l7-load-balancer] (L7LB Proxy Port: 18133)
10.69.50.209:443/TCP  0.0.0.0:0 (46) [LoadBalancer, l7-load-balancer] (L7LB Proxy Port: 18133)

cilium service list (gateway entries):
39   10.43.126.177:80/TCP     ClusterIP      (no backends)
40   10.43.126.177:443/TCP    ClusterIP      (no backends)
41   0.0.0.0:31148/TCP        NodePort       (no backends)
43   0.0.0.0:31309/TCP        NodePort       (no backends)
45   10.69.50.209:80/TCP      LoadBalancer   (no backends)
46   10.69.50.209:443/TCP     LoadBalancer   (no backends)
```

The BPF LB map correctly marks the VIP as `l7-load-balancer` with L7LB Proxy Port 18133.
This means BPF should redirect traffic to the envoy proxy on port 18133.

**However**, `cilium status` reports: `Proxy Status: OK, ip 10.42.0.237, 0 redirects active on ports 10000-20000, Envoy: external`

**0 redirects active** - the proxy port 18133 is configured in the BPF map but NOT actually bound/active.
The L7 redirect chain is broken: BPF knows where to send traffic, but the receiving end isn't set up.

### Why the Proxy Port Isn't Active

The CiliumEnvoyConfig exists and has proper listener/route/cluster config. The envoy DaemonSet
receives xDS configuration and successfully binds its listener. But the Cilium agent doesn't
establish the proxy port redirect.

This appears to be a limitation or bug in Cilium 1.19.0 with:
- Gateway API (`gatewayAPI.enabled: true`)
- External envoy DaemonSet (`envoy.enabled: true`)
- Non-hostNetwork mode (`gatewayAPI.hostNetwork.enabled: false`)

In this configuration, the gateway service has no traditional Kubernetes Endpoints/EndpointSlice
(the service has no selector). Traffic is supposed to flow entirely through BPF L7 redirect,
but the redirect isn't being activated.

### Additional Issue: RKE2 Built-in Nginx Ingress

RKE2 ships with its own nginx ingress controller (`rke2-ingress-nginx`) which claims HostPort
on 0.0.0.0:80 and 0.0.0.0:443:

```
18   0.0.0.0:80/TCP    HostPort   1 => 10.42.1.240:80/TCP (active)
20   0.0.0.0:443/TCP   HostPort   1 => 10.42.1.240:443/TCP (active)
```

This should be disabled on the kcs cluster since it uses Gateway API. It's not causing the
current issue (the VIP-specific BPF entries should take precedence over the wildcard HostPort),
but it's unnecessary and could cause confusion.

To disable: set `disable: rke2-ingress-nginx` in the RKE2 server config (NixOS).

## Changes Made During This Session

### 1. Removed hardcoded k8sServiceHost from cilium profiles

Files changed:
- `iac/helmfile/values/cilium/profile-bgp-simple.yaml` - removed `k8sServiceHost: k8s-master.mesh-k8s.example.com`
- `iac/helmfile/values/cilium/profile-gateway-bgp.yaml` - removed `k8sServiceHost: k8s-master.support.example.com`
- `iac/helmfile/values/cilium/profile-istio-bgp.yaml` - removed `k8sServiceHost: k8s-master.mesh-k8s.example.com`

These were cluster-specific values that should only come from the per-cluster generated
helmfile-values.yaml via `--state-values-file`. The helmfile template already injects
k8sServiceHost via a `set` block.

### 2. Disabled gatewayAPI.hostNetwork

File: `iac/helmfile/values/cilium/profile-gateway-bgp.yaml`
- Changed `gatewayAPI.hostNetwork.enabled` from `true` to `false`
- Rationale: hostNetwork mode creates ClusterIP service, preventing BGP advertisement of LB IP
- Result: service changed to LoadBalancer, VIP assigned and advertised via BGP
- Problem: envoy L7 redirect doesn't work without hostNetwork (see root cause above)

### 3. Added envoy keepNetBindService

File: `iac/helmfile/values/cilium/profile-gateway-bgp.yaml`
- Added `envoy.securityContext.capabilities.keepNetBindService: true`
- The cilium-envoy-starter drops all capabilities after forking envoy
- `keepNetBindService` passes NET_BIND_SERVICE to the envoy process so it can bind ports 80/443
- This fixed the "Permission denied" error when envoy tried to bind privileged ports

### 4. Fixed external-dns txtOwnerId conflict

Both kss and kcs clusters had `--txt-owner-id=k8s-cluster-kss`, causing them to delete each
other's DNS records in an infinite loop. Redeployed external-dns on kcs with correct state
values file, which set `--txt-owner-id=k8s-cluster-kcs`.

## Paths Forward

### Option A: Switch kcs to bgp-simple profile (Recommended - pragmatic)

Use Cilium for CNI + BGP, but nginx-ingress for HTTP routing instead of Gateway API.

- Change `iac/clusters/kcs/cluster.yaml`: `helmfile_env: bgp-simple`
- Regenerate: `make CLUSTER=kcs generate-cluster`
- Redeploy: `make CLUSTER=kcs deploy`
- This is proven to work (bgp-simple uses traditional LoadBalancer services with backends)
- Loses: Gateway API features (HTTPRoute, traffic splitting, etc.)
- Gains: reliability, simpler debugging

### Option B: hostNetwork + externalIPs workaround

Keep Gateway API but work around the LB issue:

- Revert `gatewayAPI.hostNetwork.enabled` back to `true`
- Envoy binds on host ports 80/443 directly (works, tested)
- Create a separate Service with `type: LoadBalancer` and `externalIPs` pointing to a node
- OR: configure BGP to advertise node IPs directly (not a service VIP)
- OR: use DNS pointing to node IPs (simplest, but no failover)
- Tradeoff: no automatic LB IP, manual node targeting

### Option C: Dedicated envoy per gateway (needs investigation)

Cilium may support a "dedicated proxy" mode where it creates a per-gateway Deployment
instead of using the shared DaemonSet. This would give the gateway its own pods that
serve as traditional service backends.

- Investigate: `gatewayAPI.gatewayClass` settings, CiliumGatewayClassConfig CRD
- May require different Cilium chart configuration
- Might not be available in 1.19.0

### Option D: Wait for Cilium fix / upgrade

The 0-redirects-active issue might be a bug in Cilium 1.19.0 with non-hostNetwork Gateway API.

- Check Cilium GitHub issues for similar reports
- Try Cilium 1.19.1+ if available
- The Gateway API implementation is still maturing in Cilium

### Option E: Hybrid - nginx-ingress with Gateway API CRDs

Use nginx-ingress for actual traffic routing (LoadBalancer service, BGP advertised),
but also install Gateway API CRDs for future migration. HTTPRoutes wouldn't work, but
Ingress resources would.

## Other TODO Items for kcs

- Disable rke2-ingress-nginx on kcs nodes (NixOS RKE2 server config: `disable: rke2-ingress-nginx`)
- Consider per-cluster domain filtering for external-dns (`--domain-filter=mesh-k8s.example.com`)
  as an additional safety layer beyond txtOwnerId
