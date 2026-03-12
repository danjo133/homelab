# Kubernetes Homelab - Specification Kit (SPEC-KIT)

## Hardware Requirements

### Workstation (Host Machine)
- **OS**: Arch Linux
- **RAM**: Minimum 48GB (8GB × 6 VMs)
  - Supporting Systems VM: 8GB
  - K8s Master: 8GB
  - K8s Workers (3×): 8GB each
- **CPU**: Multi-core (4+ cores recommended)
- **Storage**: 200GB+ free space for VM images and data
- **Network**: Gigabit Ethernet with bridge networking support
- **Virtualization**: VirtualBox with bridge adapter

### Virtual Machines (Vagrant-managed)
- **OS**: NixOS (latest stable)
- **Boot**: UEFI
- **Network**: Bridged to host network
- **Storage**: QCOW2 format, dynamic allocation

## Network Specification

### IP Address Allocation

#### Supporting Systems VM
- **VM Name**: `supporting-systems`
- **Hostname**: `support.example.com`
- **Expected IPs**: DHCP via bridge (static via DHCP reservation recommended)

#### Kubernetes Nodes
- **Master Node**
  - **VM Name**: `k8s-master`
  - **Hostname**: `k8s-master.example.com`
- **Worker Nodes (3)**
  - **VM Names**: `k8s-worker-{1,2,3}`
  - **Hostnames**: `k8s-worker-{1,2,3}.example.com`
- **All**: DHCP via bridge (static via DHCP reservation recommended)

### DNS Configuration
- **Zone**: `example.com` managed by Unifi DNS
- **Root Domain**: `example.com` managed by CloudFlare
- **Service FQDN**: `*.support.example.com`
- **Script**: Update Unifi DNS records post-VM creation
- **Alternative**: Manual DNS entries if scripting Unifi API is cumbersome

### BGP Configuration
- **Requirement**: Unifi router must support BGP
- **Purpose**: Announce Kubernetes LoadBalancer IPs
- **Configuration**: Manual setup via Unifi UI or API

## Vault Specification

### Installation
- **Version**: Latest stable (track via Renovate)
- **Deployment**: NixOS systemd service on supporting-systems VM
- **Storage**: File-based (upgradeable to raft for HA)
- **Port**: 8200 (internal), exposed via reverse proxy

### Configuration

#### PKI Setup
- **CA Certificate**: Self-signed for internal use
- **Intermediate CA**: For Kubernetes internal services
- **Wildcard Cert**: Issued for `*.support.example.com` (requires DNS01 with CloudFlare)
- **TTL**: 30 days for intermediate, 90 days for end-entity

#### Authentication Methods
- **Kubernetes Auth**: Bound to `external-secrets` ServiceAccount
- **TLS Certificates**: For service-to-service communication
- **AppRole**: For automated service authentication

#### Policy Configuration
- **external-secrets policy**: Read-only access to secrets path
- **Kubernetes policy**: Permission to use Kubernetes auth method

### Secrets Structure
```
secret/data/
├── kubernetes/
│   ├── harbor-creds
│   ├── registry-ca
│   └── vault-ca
├── helm/
│   ├── sealed-secrets-key
│   └── argocd-ssh-key
└── services/
    ├── minio-credentials
    ├── loki-encryption
    └── cloudflare-api-key
```

## Harbor Specification

### Installation
- **Version**: Latest stable (track via Renovate)
- **Deployment**: NixOS on supporting-systems VM
- **Storage**: MinIO backend for artifact storage
- **Port**: 443 (HTTPS with self-signed cert initially)

### Configuration

#### Registry Mirroring
- **Docker Hub**: Configure as proxy cache
- **Quay.io**: Configure as proxy cache
- **Rancher Registry**: Configure as proxy cache

#### Security
- **Admin Account**: Stored in Vault
- **Service Accounts**: For Kubernetes image pulls
- **SSL/TLS**: Self-signed cert issued by Vault PKI

#### Integration with Kubernetes
- **imagePullSecrets**: For private image pulls
- **Registry CA**: Distributed to Kubernetes nodes
- **Scanning**: Trivy integration for vulnerability scanning

## MinIO Specification

### Installation
- **Version**: Latest stable (track via Renovate)
- **Deployment**: NixOS on supporting-systems VM
- **Storage**: 100GB+ local block storage
- **Port**: 9000 (API), 9001 (Console)

### Configuration

#### Buckets
- **loki**: For Loki log storage (encrypted)
- **backups**: For cluster backup/restore
- **helm-artifacts**: For custom Helm charts (optional)

#### Security
- **Access Keys**: Generated at install, stored in Vault
- **Encryption**: AES-256 for data at rest
- **Policies**: IAM policies for Loki and backup access

#### Kubernetes Integration
- **App-Level Config**: Loki configured to use MinIO (not StorageClass)
- **Backup Tool**: Velero or similar for cluster backups

## NFS Specification

### Installation
- **Version**: NFSv4 with Kerberos support (optional)
- **Deployment**: NixOS on supporting-systems VM
- **Storage**: 500GB+ for legacy workloads and backups
- **Port**: 2049 (NFS)

### Configuration

#### Export Points
- `/export/kubernetes-rwx`: For Kubernetes RWX access
- `/export/backups`: For backup targets

#### Access Control
- **Kubernetes Integration**: Via NFS provisioner (nfs-subdir-external-provisioner)
- **CIDR Restrictions**: Limit to Kubernetes cluster network

## RKE2 Specification

### Installation Requirements
- **Version**: Latest stable (track via Renovate)
- **Channel**: Release (not alpha/beta)
- **CNI**: Cilium (disabled in RKE2, installed via Helm)

### Node Configuration

#### Master Node
- **Role**: control-plane
- **Taints**: `node-role.kubernetes.io/control-plane:NoSchedule`
- **Resource Requests**: 2 CPU, 2GB RAM minimum (before workloads)
- **Capabilities**: API server, controller-manager, scheduler, etcd

#### Worker Nodes
- **Role**: worker
- **Labels**: Ready to accept application workloads
- **Resource Requests**: 1 CPU, 512MB RAM minimum

### kubeconfig
- **Location**: `/etc/rancher/rke2/rke2.yaml`
- **Access**: From Vault CA for external connections
- **Permissions**: Restricted to node operator account

## Cilium & Tetragon Specification

### Cilium Installation
- **Version**: Latest stable (track via Renovate)
- **Deployment**: Via Helmfile during bootstrap
- **CNI**: Replaces default flannel/weave
- **Features**: NetworkPolicy, BGP routing, Ingress

### Tetragon Installation
- **Version**: Latest stable
- **Deployment**: Via Helm (post-Cilium)
- **Purpose**: Runtime pod hardening and visibility
- **Policies**: Custom policies for application security

## cert-manager Specification

### Installation
- **Version**: Latest stable (track via Renovate)
- **Deployment**: Via Helmfile during bootstrap
- **Issuers**: Let's Encrypt (staging and production)

### ClusterIssuer Configuration

#### Wildcard Certificate
- **Domain**: `*.support.example.com`
- **Solver**: DNS01 (CloudFlare)
- **API Token**: Stored in Vault, injected via external-secrets
- **Renewal**: 30 days before expiration

## External Secrets Operator Specification

### Installation
- **Version**: Latest stable (track via Renovate)
- **Deployment**: Via Helmfile or ArgoCD
- **Backend**: Vault with Kubernetes auth

### SecretStore Configuration
- **Name**: `vault-backend`
- **Namespace**: `external-secrets`
- **Auth**: Kubernetes ServiceAccount with Vault role

### Sync Patterns
- **Refresh Interval**: 1 hour
- **Retry**: 15 seconds on failure

## ArgoCD Specification

### Installation
- **Version**: Latest stable (track via Renovate)
- **Deployment**: Via Helmfile during bootstrap
- **Namespace**: `argocd`

### Repository Configuration
- **Git Repository**: Main source of truth for cluster configuration
- **HTTPS**: With SSH key stored in Vault
- **Webhook**: Optional, for immediate sync on push

### Application Management
- **Bootstrap Apps**: Core services via Helmfile
- **GitOps Apps**: Remaining services via ArgoCD ApplicationSets

## Observability Stack Specification

### Prometheus
- **Version**: Latest stable
- **Scrape Interval**: 30 seconds
- **Retention**: 15 days local storage
- **Storage**: 50GB PVC (Longhorn)

### Grafana
- **Version**: Latest stable
- **Data Source**: Prometheus
- **Dashboards**: Kubernetes cluster monitoring, application dashboards
- **Authentication**: OIDC via external provider (optional)

### Loki
- **Version**: Latest stable
- **Storage**: MinIO (S3-compatible)
- **Retention**: 30 days
- **Encryption**: AES-256 at rest in MinIO
- **Index**: LokiStack with BoltDB Shipper

### Collector
- **Promtail**: Log collection from all pods and nodes
- **Alternative**: Fluent-bit for lighter footprint

## Trivy Operator Specification

### Installation
- **Version**: Latest stable (track via Renovate)
- **Deployment**: Via ArgoCD post-bootstrap
- **Scanning Frequency**: Daily for all images

### Configuration
- **Registry**: Harbor for private images
- **Reports**: VulnerabilityReport and ExposureReport CRDs
- **Action**: Alert on critical/high findings

## Storage Specification

### Longhorn
- **Version**: Latest stable (track via Renovate)
- **Deployment**: Via ArgoCD post-bootstrap
- **Replicas**: 3 (recommended minimum)
- **Storage**: 100GB per worker node

### MinIO
- Reference: See "MinIO Specification" above

### NFS
- Reference: See "NFS Specification" above

## Helmfile & Kustomize Specification

### Bootstrap Helmfile
- **Location**: `./helmfile/bootstrap.yaml`
- **Releases**:
  1. Cilium (CNI)
  2. Tetragon (pod hardening)
  3. cert-manager (certificate management)
  4. external-secrets (secret injection)
  5. ArgoCD (GitOps)
  6. Nginx Ingress (ingress controller)

### Kustomize Patches
- **Location**: `./kustomize/overlays/{dev,prod}/`
- **Purpose**: Environment-specific customizations
- **Examples**: Replica counts, resource limits, domain names

## Git Repository Requirements

### Structure
```
iac/
├── docs/
│   ├── ARCHITECTURE.md
│   ├── SPEC-KIT.md
│   └── TODO.md
├── provision/
│   ├── nix-flake/
│   │   ├── supporting-systems/
│   │   ├── k8s-master/
│   │   └── k8s-worker/
│   ├── scripts/
│   └── Vagrantfile
├── helmfile/
│   ├── bootstrap.yaml
│   └── values/
├── kustomize/
│   ├── base/
│   └── overlays/
├── Makefile
├── .renovaterc.json
├── .trivy.yaml
└── flake.nix
```

### Git Configuration
- **Remote**: Push all changes to main branch
- **Commits**: Semantic commit messages
- **Tags**: Version tags for releases
- **CI/CD**: GitHub Actions for testing and scanning

## Renovate Configuration

### Update Strategy
- **Dependencies**: Kubernetes, RKE2, all Helm charts
- **Schedule**: Weekly updates on Monday morning
- **Groups**: Group patch updates, separate minor/major
- **Auto-merge**: Patch updates only, minor/major require review

### Scanning Targets
- **Dockerfile**: All service images
- **Helm Charts**: Values and dependencies
- **NixOS packages**: Via Flake inputs
- **GitHub Actions**: Workflow updates

## Trivy Scanning Configuration

### Targets
- **Container Images**: All images pulled into Harbor
- **Kubernetes Manifests**: Policy violations
- **Helm Charts**: Misconfigurations
- **Repository**: Configuration and dependency vulnerabilities

### Thresholds
- **Critical**: Block deployment
- **High**: Require manual approval
- **Medium**: Log and track
- **Low**: Informational only

## Backup & Recovery Specification

### Backup Strategy
- **Application Data**: Daily snapshots via Longhorn
- **Cluster Configuration**: Continuous via GitOps (Git)
- **Secrets**: Replicated to Vault backup
- **Logs**: Retained in MinIO per policy

### Recovery Procedures
- **RTO**: 4 hours (restore cluster from scratch)
- **RPO**: 1 hour (incremental backups)
- **Automation**: Runbooks in repository

## Security Policies

### Image Security
- **Base Images**: Minimal distros (Alpine, Distroless, NixOS)
- **Scanning**: Trivy scanning before deployment
- **Registry**: Harbor with RBAC and audit logging

### Network Security
- **Cilium NetworkPolicies**: Deny-all default, explicit allow rules
- **Encryption**: In-transit with TLS, at-rest with encrypted storage

### Access Control
- **RBAC**: Least-privilege Kubernetes RBAC
- **ServiceAccounts**: Dedicated accounts per application
- **Vault Auth**: Kubernetes auth method with token review

### Compliance
- **Audit Logging**: Kubernetes API audit logs
- **Image Scanning**: Regular CVE scanning
- **Configuration**: Policy as code with OPA (future)

## Performance Targets

### Cluster Metrics
- **API Latency**: <100ms p50, <500ms p99
- **Pod Startup**: <5 seconds average
- **Network Bandwidth**: >500 Mbps intra-cluster

### Storage Metrics
- **Longhorn IOPS**: >1000 IOPS per node
- **MinIO Throughput**: >100 MB/s
- **NFS Throughput**: >50 MB/s

## Maintenance Windows

### Regular Maintenance
- **Kubernetes Upgrades**: Monthly (with 2-week notice)
- **Application Updates**: Weekly via Renovate
- **Security Patches**: Within 7 days of release
- **Log Rotation**: Automated, 30-day retention

### Validation
- **Post-Deployment**: Run smoke tests
- **Health Checks**: Continuous monitoring
- **Backup Verification**: Monthly restore test

## Version Constraints

### Pinned Versions
All component versions should be pinned and tracked by Renovate for predictable upgrades:
- RKE2: Latest stable minor release
- Helm Charts: Latest compatible minor release
- NixOS: Latest stable branch
- Kubernetes components: Determined by RKE2 version
