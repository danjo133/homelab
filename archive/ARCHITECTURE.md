# Kubernetes Homelab Infrastructure Architecture

## Overview

This document describes a modern, secure Kubernetes setup designed for homelab experimentation with a path to production-grade infrastructure.

## Network Topology

```
Internet
  ↓
Unifi Router (DNS, BGP routing)
  ↓
Workstation (Arch Linux, Vagrant, 8GB+ RAM per VM)
  ├── Supporting Systems VM (NixOS)
  │   ├── Vault (PKI, secrets management)
  │   ├── Harbor (artifact repository)
  │   ├── MinIO (object storage)
  │   └── NFS (shared storage)
  └── Kubernetes Cluster (RKE2 on NixOS VMs)
      ├── 1x Master Node (8GB RAM)
      └── 3x Worker Nodes (8GB RAM each)
```

## Base Domain Structure

- **Root Domain**: `example.com` (Cloudflare-managed)
- **Subdomain**: `example.com` (Unifi-managed)
- **Kubernetes Services**: `support.example.com`

## Component Descriptions

### Supporting Systems VM
Single NixOS VM hosting infrastructure dependencies:

#### Vault
- **Purpose**: PKI, credential management, secrets store
- **URL**: `trust.support.example.com`
- **Kubernetes Integration**: Auth backend for service accounts
- **Certificates**: Issues certificates for internal services

#### Harbor
- **Purpose**: Private container artifact repository
- **URL**: `artifacts.support.example.com`
- **Configuration**: Pull-through cache for Docker Hub, Rancher, Quay
- **Kubernetes Integration**: Registry authentication and CA trust

#### MinIO
- **Purpose**: S3-compatible object storage
- **Use Cases**: Loki log storage (encrypted), backups
- **Kubernetes Integration**: App-level configuration (not StorageClass)

#### NFS Server
- **Purpose**: Shared RWX storage for legacy workloads and backups
- **Kubernetes Integration**: Via NFS provisioner

### Kubernetes Cluster

#### Nodes
- 1 Master node (control plane)
- 3 Worker nodes (application workloads)
- All running NixOS with RKE2

#### Container Network Interface (CNI)
- **Primary**: Cilium with Tetragon hardening
- **Alternative**: Can be switched to nginx/Gateway API ingress

#### Cluster Components

##### Security & Certificates
- **cert-manager**: Manages Let's Encrypt wildcard certificates for `*.support.example.com`
- **DNS01 Challenge**: CloudFlare handles DNS validation for `example.com`
- **External Secrets Operator**: Fetches secrets from Vault

##### Observability
- **Prometheus**: Metrics collection
- **Grafana**: Visualization and dashboarding
- **Loki**: Log aggregation (encrypted storage on MinIO)
- **Trivy Operator**: Container vulnerability scanning

##### Storage
- **Longhorn**: Default PersistentVolume provisioner for application state
- **MinIO**: Object store for Loki (via app configuration)
- **NFS**: RWX access for legacy workloads

##### Ingress & Service Mesh
- **Nginx Ingress**: Alternative to Cilium Ingress
- **Gateway API**: Optional modern ingress API
- **BGP Routing**: Unifi router routes LoadBalancer IPs via BGP

##### Configuration Management
- **ArgoCD**: Declarative GitOps for cluster configurations
- **Helmfile**: Initial cluster bootstrap (Cilium, Tetragon, ArgoCD, Nginx, RBAC)
- **Kustomize**: Configuration customization

## Installation Sequence

### Phase 1: Supporting Infrastructure
1. Bring up Supporting Systems VM
2. Install and configure Vault
   - PKI setup
   - Kubernetes authentication role
3. Install Harbor with pull-through cache
4. Install MinIO and NFS server

### Phase 2: Kubernetes Cluster
1. Bring up Kubernetes VMs (1 master, 3 workers)
2. Install RKE2 on all nodes
3. Configure kube-apiserver to trust Vault CA
4. Setup Harbor registry authentication and imagePullSecrets
5. Install cert-manager with CloudFlare DNS01 solver
6. Install external-secrets-operator
7. Bootstrap ArgoCD for GitOps management

### Phase 3: Cluster Services (via Helmfile)
1. Install Cilium CNI with Tetragon
2. Install cert-manager and external-secrets
3. Install ArgoCD
4. Install Nginx Ingress Controller
5. Setup RBAC policies

### Phase 4: Cluster Services (via ArgoCD)
1. Deploy Prometheus and Grafana
2. Deploy Loki with encrypted MinIO storage
3. Deploy Trivy Operator
4. Deploy Longhorn
5. Deploy application workloads

## Deployment Commands

```bash
# Bring up all VMs
make up

# Provision VMs with NixOS and services
make provision

# Reset infrastructure (destroy and recreate)
make reset
```

## Networking Considerations

### Bridge Network Configuration
- All VMs use bridge networking on the workstation
- Kubernetes services accessible via LoadBalancer IPs
- Unifi router announces routes via BGP for direct access
- DNS entries in Unifi DNS server for Vagrant-based services

### DNS Resolution
- **External**: CloudFlare DNS for `example.com`
- **Internal**: Unifi DNS server for `example.com` subdomains
- **ExternalDNS**: Unifi webhook integration for dynamic DNS updates from Kubernetes

## Security Principles

1. **Vault-first**: All credentials stored in Vault, fetched by external-secrets
2. **Certificate Management**: Let's Encrypt with automated renewal via cert-manager
3. **Pod Security**: Tetragon provides runtime hardening and monitoring
4. **Supply Chain**: Trivy operator scans all container images for vulnerabilities
5. **Registry Security**: Harbor provides CA trust and image scanning
6. **Network Policy**: Cilium enables fine-grained network policies

## Scalability Path to Production

The current setup is designed to scale:

1. **Replace single workstation** with multiple hypervisor hosts
2. **Supporting Services VM** can be split into separate VMs per service
3. **Kubernetes cluster** can expand with more worker nodes
4. **Storage** can migrate to dedicated NFS/MinIO infrastructure
5. **Networking** can integrate with production BGP/DNS infrastructure

## Technology Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| OS | NixOS | Declarative infrastructure |
| VM Management | Vagrant | Reproducible VM provisioning |
| Container Runtime | containerd (via RKE2) | Container execution |
| CNI | Cilium | Networking and security policies |
| Pod Hardening | Tetragon | Runtime security |
| Certificate Management | cert-manager | TLS automation |
| Secrets Management | Vault + external-secrets | Credential management |
| GitOps | ArgoCD | Declarative deployments |
| Package Management | Helmfile + Helm | Kubernetes package management |
| Monitoring | Prometheus + Grafana | Metrics and visualization |
| Logging | Loki | Log aggregation |
| Vulnerability Scanning | Trivy | Container image scanning |
| Storage | Longhorn + MinIO + NFS | Persistent storage |
| Registry | Harbor | Private artifact repository |

## Future Enhancements

- Implement Backup/Restore strategy using MinIO and Longhorn
- Setup Chaos Engineering with Litmus or Gremlin
- Implement multi-cluster setup with Cilium ClusterMesh
- Add ServiceMesh (Cilium or Istio) for advanced traffic management
- Implement compliance scanning (Falco, OPA/Gatekeeper)
