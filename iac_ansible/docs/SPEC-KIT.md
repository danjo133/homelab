# Spec-Kit: Requirements and Checklist

This spec-kit lists hardware, software, network, and operational requirements to run the lab cluster and expand it to production.

Hardware
- Workstation: x86_64 with >=32GB RAM recommended for 4-node cluster (8GB each) + host usage. More for production.
- SSD storage, recommended >= 250GB for logs and images.

Software (Host)
- Arch Linux (as requested)
- Vagrant
- VirtualBox or libvirt (host provider)
- bridge-utils or NetworkManager configured bridge (e.g., `br0`)

Software (VMs)
- Ubuntu 22.04 LTS (or other supported Linux)
- RKE2 server and agent
- Cilium with Tetragon (Helm)
- optional: FRR/BIRD for BGP (or MetalLB in BGP mode)
 - HashiCorp Vault (KV v2) for secrets and PKI. In lab mode we run a dev Vault in a VM; for production use a proper HA Vault cluster.
 - JFrog Artifactory (OSS) for artifact storage (lab uses a single-node containerized Artifactory)

Networking
- Bridge network on host to place VMs on LAN
- BGP peering: UniFi router must accept BGP or we can run a BGP speaker on host/cluster
- Required ports: 6443 (k8s API), 9345 (rke2 server), etcd ports if external, node ports for services

Security & Hardening
- Use Cilium with Hubble for observability
- Enable Tetragon for runtime enforcement
- Pod Security Policies / OPA Gatekeeper
- Regular OS updates and image hardening

Operational
- Backup strategy for cluster state and persistent volumes
- Monitoring (Prometheus + Grafana) and logging (EFK or Loki)
- CI/CD integration for manifests
- Upgrade plan for RKE2 and Cilium
 - Credential management: the provisioning scripts support storing RKE2 tokens + kubeconfig into Vault KV v2. Set `VAULT_ADDR` and `VAULT_TOKEN` on the master VM before provisioning to enable. Set `NO_DISK_SECRETS=1` to avoid leaving kubeconfig on disk.

Checklist for production expansion
- Migrate VMs to dedicated physical hosts
- Use HA control plane (3 control plane nodes)
- Use dedicated etcd or RKE2 HA configuration
- Secure network segmentation and firewalling
- BGP integration and IP management

References
- RKE2 docs: https://docs.rke2.io
- Cilium docs: https://cilium.io
- Tetragon docs: https://cilium.io/docs/tetragon
