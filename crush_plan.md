# Cilium and API Gateway BGP Upgrade Plan

## Current State

- **Task**: Upgrade Cilium and API Gateway to support BGP
- **Current Progress**: Initial investigation of cluster state and existing configurations
- **What's being worked on right now**: Analyzing current Cilium version (1.16.19) and Gateway API setup to determine upgrade requirements
- **What remains to be done**:
  - Determine if Cilium needs upgrading to newer version for better BGP support
  - Verify Gateway API CRD compatibility
  - Check for any configuration issues preventing BGP route advertisement
  - Apply necessary upgrades and configurations

## Files & Changes

- **Files read/analyzed**:
  - `/home/admin/mnt/kss/iac/helmfile/values/cilium/profile-gateway-bgp.yaml` - Cilium configuration profile with BGP and Gateway API enabled
  - `/home/admin/mnt/kss/iac/kustomize/base/gateway-api-crds/kustomization.yaml` - Gateway API CRDs configuration (v1.1.0)
  - `/home/admin/mnt/kss/iac/kustomize/base/cilium/bgp-peering-policy.yaml` - BGP peering policy configuration
  - `/home/admin/mnt/kss/iac/kustomize/base/gateway/gateway.yaml` - Gateway API Gateway resource

- **Key files not yet touched**:
  - `/home/admin/mnt/kss/iac/helmfile/values/cilium/common.yaml` - Base Cilium configuration
  - `/home/admin/mnt/kss/iac/helmfile/values/cilium/profile-base.yaml` - Base profile
  - `/home/admin/mnt/kss/iac/helmfile/values/cilium-standalone-full.yaml` - Full standalone profile

- **Important code locations**:
  - Cilium config: `kube-system/cilium-config` ConfigMap
  - BGP peering policy: `kube-system` namespace
  - Gateway API CRDs: Applied from v1.1.0 experimental channel

## Technical Context

- **Architecture**: RKE2 Kubernetes cluster (v1.31.4+rke2r1) with 4 nodes (1 master, 3 workers)
- **Cilium version**: 1.16.19 (installed 34h ago)
- **Cilium namespace**: kube-system
- **Gateway API version**: v1.1.0 (experimental channel)
- **BGP configuration**:
  - BGP control plane enabled: true
  - Local ASN: 64513
  - Peer ASN: 64512 (UniFi router)
  - Peer address: 10.69.50.1:179
  - Session status: active (0s uptime)
  - Routes advertised: 0 (no LoadBalancer services deployed yet)
- **CiliumLoadBalancerIPPool**: `default-pool` with 20 IPs available
- **Gateway API resources**:
  - GatewayClass: `cilium` (controller: io.cilium/gateway-controller, Accepted: True)
  - Gateway: `main-gateway` in kube-system namespace
  - HTTPRoute: `http-to-https-redirect` in kube-system namespace
- **Environment**: NixOS 26.05 (Yarara) on all nodes, containerd://1.7.23-k3s2
- **Commands executed**:
  - `kubectl get nodes -o wide` - Verified cluster state
  - `kubectl get pods -n kube-system | grep cilium` - Confirmed Cilium pods running
  - `kubectl get cm -n kube-system cilium-config -o yaml | grep -E "version|bgp"` - Checked BGP and version config
  - `kubectl exec -n kube-system cilium-kxtnx -- cilium version` - Retrieved Cilium version
  - `kubectl get crd | grep -i ciliumloadbalancer` - Verified CiliumLoadBalancerIPPool CRD
  - `kubectl get ciliumloadbalancerippools.cilium.io` - Checked IP pool status
  - `kubectl get crd | grep gateway` - Verified Gateway API CRDs
  - `kubectl get gatewayclass` - Checked GatewayClass
  - `kubectl get gateway` - Checked Gateway resources
  - `kubectl get httproute` - Checked HTTPRoute resources
  - `kubectl exec -n kube-system cilium-kxtnx -- cilium bgp peers` - Checked BGP peer status
  - `kubectl logs -n kube-system cilium-operator-54dfb45456-8hrz4 --tail=50 | grep -iE "bgp|gateway|error"` - Checked for errors

- **Commands that failed**:
  - `kubectl exec -n kube-system cilium-kxtnx -- cilium version --json` - Unknown flag `--json`

## Strategy & Approach

- **Overall approach**:
  1. Assess current Cilium and Gateway API versions for compatibility
  2. Check if BGP is properly configured and advertising routes
  3. Identify any Gateway API configuration issues
  4. Upgrade to compatible versions if needed
  5. Verify BGP route advertisement after upgrade

- **Key insights**:
  - Cilium 1.16.19 is installed with BGP control plane enabled
  - Gateway API CRDs are at v1.1.0 (Cilium 1.16.x compatible version)
  - BGP peer is established but no routes are being advertised (expected since no LoadBalancer services)
  - Gateway API reconciliation shows some errors: "model source can't be empty" for HTTPRoute
  - CiliumLoadBalancerIPPool CRD exists with 20 IPs available
  - Gateway API is enabled in Cilium config with all required flags

- **Assumptions**:
  - User wants to use BGP for LoadBalancer service IP advertisement
  - Gateway API will be used for ingress routing
  - Current Cilium version may need upgrade for better BGP support

- **Blockers identified**:
  - Gateway API HTTPRoute reconciliation errors need investigation
  - No routes being advertised via BGP (expected but needs verification)
  - Need to determine if Cilium upgrade is necessary

## Exact Next Steps

1. Check current Cilium version compatibility with Gateway API v1.1.0 and BGP features
2. Review Gateway API HTTPRoute error logs to understand "model source can't be empty" issue
3. Check if there are any missing Gateway API resources or configurations
4. Determine if Cilium upgrade is needed (check for newer stable releases)
5. Review and update Cilium configuration if needed for BGP optimization
6. Test BGP route advertisement with a sample LoadBalancer service
7. Verify Gateway API functionality after any upgrades