# Architecture Overview

Goal: Provide a reproducible, bridged RKE2 cluster running Cilium + Tetragon on a workstation (Arch Linux). The design targets later expansion to multiple physical hosts.

Topology
- Internet -> UniFi router -> Workstation (host) -> VMs for k8s nodes
- VMs use bridged networking (host bridge) so they appear on the same L2 network as the router.

Nodes
- 1 control-plane (k8s-master)
- 3 worker nodes (k8s-worker1..3)
- Each VM default: 8GB RAM, 4 vCPUs (configurable via env vars)

Networking
- Vagrant VMs configured with `public_network` (bridged) to attach to the host bridge (e.g., `br0`).
- This allows BGP advertisements from VMs or routing from the UniFi device to the VMs' IPs.
- For BGP, run a BGP daemon (e.g., FRR, Bird) as a DaemonSet in the cluster or on the host. Recommend using MetalLB with BGP speaker mode or Cilium's BGP integration.

Kubernetes
- RKE2 is installed on the master (server) and agents on the workers.
- kubeconfig is exported to `/vagrant/kubeconfig` for access from the host.
 - Optionally, use HashiCorp Vault to store RKE2 token and kubeconfig so no credentials are written to disk. The provisioning scripts support `VAULT_ADDR` and `VAULT_TOKEN` environment variables; when provided the master uploads credentials to Vault and removes the local kubeconfig if `NO_DISK_SECRETS=1` is set.

Service mesh & hardening
- Deploy Cilium as the CNI and service mesh.
- Enable Tetragon (Cilium's runtime security) alongside Cilium for pod hardening and runtime observability.

Extensibility
- Replace the single workstation with multiple physical hosts by moving VMs to dedicated hosts or converting VMs to bare-metal installs.
- Use the same RKE2 installation and Cilium/Tetragon manifests.

Security
- Use least privilege for Kubernetes RBAC.
- Use restricted PodSecurity or OPA/Gatekeeper for admission control.
- Use TLS for etcd and APIserver as configured by RKE2.

Operational notes
- Backup `/vagrant/kubeconfig` and token before tearing down.
- Use `vagrant suspend` / `vagrant halt` for maintenance.
