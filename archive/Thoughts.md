Kubernetes Edge Connectivity Design

Expose Kubernetes services cleanly in a homelab using:

* Cilium for networking and service LB
* BGP between Kubernetes nodes and UniFi Dream Machine (FRR)
* Cilium Gateway API (Envoy) for ingress
* ExternalDNS for DNS automation
* cert-manager for TLS (Let’s Encrypt, DNS-01)

No kube-proxy, no MetalLB, no NodePorts, no L2 hacks.

High-Level Architecture
Clients
  ↓
UniFi Dream Machine (FRR, BGP)
  ↓ (ECMP routes via BGP)
Cilium Service VIPs
  ↓
Cilium Gateway (Envoy)
  ↓
Pods

1. Networking & Routing (Cilium + BGP)
Principles:
Kubernetes LoadBalancer Services get real VIPs
Each node advertises VIPs to UniFi via BGP
UniFi installs ECMP routes
DNS never selects nodes; routing does
Required Cilium Features
BGP Control Plane enabled
kube-proxy replacement enabled
Gateway API enabled
Optional (recommended): DSR, Maglev

Behavior:
UniFi hashes flows (ECMP) → selects entry node
Cilium eBPF selects backend pod
Local pod preferred; remote pod only if necessary
Optional DSR allows pod → client direct return

2. UniFi Dream Machine (FRR)
Configuration Goals:
Enable BGP
Peer with each Kubernetes node (or route reflector)
Accept /32 routes for:
Gateway VIPs
LoadBalancer Service IPs

Outcome
UniFi routing table contains Kubernetes service VIPs
No NAT, no port forwarding
Full L3 routing

3. Ingress (Cilium Gateway API)
Design
Use Cilium Gateway API (Envoy) instead of NGINX
Create 1–3 Gateway VIPs (recommended)

Each Gateway:
Service type: LoadBalancer
VIP advertised via BGP

Benefits:
Native Cilium datapath
L7 routing + TLS termination
No extra ingress controller

4. DNS (ExternalDNS)
Principle

DNS only maps name → VIP, never to nodes.
Setup Options (pick one)
Preferred (authoritative DNS):
Run BIND / PowerDNS / Technitium
UniFi hands it out via DHCP
ExternalDNS uses RFC2136 (TSIG)
Alternative (simpler):

Use UniFi DNS
ExternalDNS UniFi webhook provider
Records Created
app.lab.example.com → <Gateway VIP>
or per-Gateway names if multiple Gateways exist

5. TLS / Certificates (cert-manager)
Approach
Use cert-manager inside Kubernetes
Use DNS-01 challenge
wildcard cert (*.support.example.com)

6. Explicit Non-Goals (Do NOT implement)

❌ MetalLB
❌ NodePort exposure
❌ Per-node DNS records
❌ DNS-based traffic steering
❌ External reverse proxy VM
❌ L2 ARP-based VIP hacks

7. Key Best-Practice Decisions (Rationale)

Single (or few) VIPs keep DNS and TLS simple
ECMP + eBPF handle load distribution efficiently
Cilium prefers local pods automatically
Routing ≠ DNS
Ingress is L7, routing is L3/L4

8. Deliverables to Implement
Kubernetes
Cilium BGP Control Plane config
Cilium Gateway API resources
Gateway Service(s) with LoadBalancer IP pools
ExternalDNS deployment + provider config
cert-manager ClusterIssuer (DNS-01)

UniFi
FRR BGP config peering with K8s nodes
Route acceptance for service VIP CIDRs

One-Sentence Summary

Use Cilium’s BGP-advertised LoadBalancer VIPs with Gateway API (Envoy), let UniFi route via ECMP, keep DNS dumb with ExternalDNS, and terminate TLS with cert-manager — no kube-proxy, no MetalLB, no NodePorts.
