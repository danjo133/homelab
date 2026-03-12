# Kubernetes Homelab - Implementation TODO List

## Phase 0: Pre-Infrastructure Setup

### Foundation Setup
- [ ] **URGENT**: Review and update SPEC-KIT.md for your specific environment
- [ ] Ensure workstation has VirtualBox installed and configured
- [ ] Create Vagrant box inventory (supporting-systems, k8s-master, k8s-worker-{1,2,3})
- [ ] Setup bridge network in VirtualBox for host-VM networking
- [ ] Configure static DHCP reservations in Unifi for VM IPs
- [ ] Test manual VM creation with Vagrant to verify environment

### Network Configuration
- [ ] Reserve IP addresses in Unifi DHCP for all VMs
- [ ] Configure Unifi DNS zone (`example.com`) with A records for:
  - [ ] `support.example.com`
  - [ ] `k8s-master.example.com`
  - [ ] `k8s-worker-{1,2,3}.example.com`
  - [ ] `*.support.example.com` (wildcard for services)
- [ ] Verify CloudFlare DNS for `example.com` is properly configured
- [ ] Document your network topology and CIDR ranges

### Git Repository Setup
- [ ] Initialize git repository (if not already done)
- [ ] Create `.gitignore` for Vagrant, VirtualBox, and local artifacts
- [ ] Setup remote repository on GitHub/GitLab/Gitea
- [ ] Push initial commit with documentation and scaffolding

---

## Phase 1: Supporting Infrastructure VM ✅ COMPLETE

### VM Creation
- [x] **Task 1.1**: Define NixOS configuration for supporting-systems VM
  - [x] Output VM configuration with NixOS module system
  - [x] Configure networking (DHCP with hostname)
  - [x] Configure SSH for remote access
  - [x] Test configuration and VM startup
- [x] **Task 1.2**: Create Vagrant configuration for supporting-systems
  - [x] Define VM specs (8GB RAM, 50GB disk)
  - [x] Configure bridge network
  - [x] Map provision scripts
  - [x] Test `vagrant up` for supporting-systems

### Vault Installation (vault.support.example.com)
- [x] **Task 1.3**: Define Vault NixOS module
  - [x] Install Vault via NixOS package (vault-bin for pre-built binary)
  - [x] Configure systemd service with auto-init and auto-unseal
  - [x] Setup file-based storage (upgradeable path noted)
  - [x] TLS termination via Nginx reverse proxy
  - [x] Enable audit logging
- [x] **Task 1.4**: Initialize and configure Vault (automated via vault.nix)
  - [x] Auto-initialize Vault on first boot (1 key share for IaC workflow)
  - [x] Auto-unseal on boot using stored keys
  - [ ] Configure Kubernetes auth method (deferred to Phase 2)
  - [x] Setup PKI: Internal Root CA
  - [x] Setup PKI: Intermediate CA for services
  - [ ] Configure AppRole for services (deferred to Phase 2)
  - [ ] Create service policies (deferred to Phase 2)
  - [x] Test Vault API connectivity from workstation
- [ ] **Task 1.5**: Create secret structure (deferred to Phase 2)
  - [ ] Vault secret paths: `secret/data/kubernetes/*`
  - [ ] Vault secret paths: `secret/data/helm/*`
  - [ ] Vault secret paths: `secret/data/services/*`
  - [x] Vault CA certificate available via PKI

### Harbor Installation (harbor.support.example.com)
- [x] **Task 1.6**: Define Harbor NixOS module
  - [x] Install Harbor via Docker Compose (auto-setup on first boot)
  - [x] Configure internal PostgreSQL backend
  - [x] Configure MinIO storage backend (optional, if credentials exist)
  - [x] TLS termination via Nginx reverse proxy
  - [x] Auto-generate admin credentials
  - [x] Trivy vulnerability scanner enabled
- [ ] **Task 1.7**: Configure Harbor registry mirrors (manual step)
  - [ ] Add Docker Hub as proxy cache
  - [ ] Add Quay.io as proxy cache
  - [ ] Add Rancher Registry as proxy cache
  - [ ] Test proxy pull
  - [ ] Create service account for Kubernetes pulls
- [ ] **Task 1.8**: Setup Harbor CA trust (deferred - using self-signed wildcard for now)
  - [ ] Export Harbor's CA certificate
  - [ ] Store in Vault
  - [ ] Distribute to Kubernetes nodes during K8s setup

### MinIO Installation (minio.support.example.com)
- [x] **Task 1.9**: Define MinIO NixOS module
  - [x] Install MinIO via NixOS package
  - [x] Configure systemd service
  - [x] Configure persistent storage
  - [x] Credentials from file (not in Nix store)
  - [ ] Configure encryption (optional)
  - [x] Logging enabled
- [ ] **Task 1.10**: Create MinIO buckets and policies (run bootstrap-minio.sh)
  - [ ] Create bucket: `harbor` (for Harbor storage)
  - [ ] Create bucket: `loki` (for Loki log storage)
  - [ ] Create bucket: `backups` (for cluster backups)
  - [ ] Create bucket: `velero` (for Velero backups)
  - [ ] Create IAM policies
  - [ ] Test S3 access with access keys
  - [ ] Store credentials in Vault

### NFS Server Installation
- [x] **Task 1.11**: Define NFS NixOS module
  - [x] Configure NFSv4 export points
  - [x] Export point: `/export/kubernetes-rwx` for RWX access
  - [x] Export point: `/export/backups` for backup targets
  - [x] Configure CIDR restrictions (10.69.50.0/24)
  - [x] Configure fixed ports for firewall compatibility
  - [x] Logging via systemd
- [ ] **Task 1.12**: Test NFS access
  - [ ] Test NFS mount from workstation
  - [ ] Test NFS mount from future Kubernetes node
  - [ ] Verify CIDR restrictions

### Nginx Reverse Proxy (added)
- [x] **Task 1.13**: Define Nginx NixOS module
  - [x] TLS termination with self-signed wildcard certificate
  - [x] Reverse proxy for Vault, MinIO, Harbor
  - [x] Recommended security settings enabled
  - [x] Auto-generate certificates on first boot

### Validation of Phase 1
- [x] Vault API is accessible via Nginx reverse proxy
- [x] Vault PKI is initialized (Root CA + Intermediate CA)
- [x] Harbor is accessible and running with Trivy
- [x] MinIO is accessible (buckets need manual creation)
- [x] NFS exports are configured (need testing from k8s nodes)
- [x] Commit all NixOS configurations to git

---

## Phase 2: Kubernetes Cluster VMs ✅ NixOS CONFIGS COMPLETE

### Master Node VM Creation
- [x] **Task 2.1**: Define NixOS configuration for k8s-master
  - [x] Output VM configuration with NixOS module system
  - [x] Configure networking (DHCP with hostname)
  - [x] Configure SSH for remote access
  - [x] Prepare for RKE2 installation (kernel modules, sysctl, packages)
  - [x] Configure Vault CA trust (auto-fetch service)
  - [x] Configure Harbor registry (registries.yaml)
  - [ ] Test configuration and VM startup
- [x] **Task 2.2**: Vagrant configuration for k8s-master (already in Vagrantfile)
  - [x] Define VM specs (8GB RAM)
  - [x] Configure bridge network
  - [ ] Test `vagrant up` for k8s-master

### Worker Node VMs Creation
- [x] **Task 2.3**: Define NixOS configuration for k8s-worker
  - [x] Output VM configuration with NixOS module system
  - [x] Configure networking (DHCP with hostname via wrapper configs)
  - [x] Configure SSH for remote access
  - [x] Prepare for RKE2 agent installation
  - [x] Configure Vault CA trust (auto-fetch service)
  - [x] Configure Harbor registry (registries.yaml)
  - [x] Configure Longhorn prerequisites (iSCSI, NFS)
  - [ ] Test configuration for all workers
- [x] **Task 2.4**: Vagrant configuration for k8s-worker-{1,2,3} (already in Vagrantfile)
  - [x] Define VM specs (8GB RAM each)
  - [x] Configure bridge network
  - [ ] Test `vagrant up` for all workers

### RKE2 Installation (automated via NixOS modules)
- [x] **Task 2.5**: RKE2 Server configuration (k8s-master)
  - [x] Auto-download RKE2 installer (v1.31.4+rke2r1)
  - [x] Configure kubeconfig path
  - [x] Disable default CNI (cni: none for Cilium)
  - [x] Configure TLS SANs for kube-apiserver
  - [x] Configure registry (Harbor mirror in registries.yaml)
  - [x] Systemd service for auto-install on first boot
  - [ ] Verify master node is running: `kubectl get nodes`
  - [ ] Extract kubeconfig for external access
- [x] **Task 2.6**: RKE2 Agent configuration (k8s-workers)
  - [x] Auto-download RKE2 installer (same version as master)
  - [x] Configure to join master via token
  - [x] Configure registry (Harbor mirror)
  - [x] Systemd service for auto-install and auto-join
  - [ ] Verify all nodes are ready: `kubectl get nodes`
- [ ] **Task 2.7**: Verify cluster health
  - [ ] Check node status: all nodes should be `Ready`
  - [ ] Check system pods: `kubectl get pods -n kube-system`
  - [ ] Verify kube-apiserver is running
  - [ ] Test API access with kubeconfig
  - [ ] Test image pull from Harbor

### Cluster Configuration (deferred to runtime)
- [ ] **Task 2.8**: Distribute join token to workers
  - [ ] Run `make k8s-distribute-token` after master is up
  - [ ] Or manually copy token file
- [ ] **Task 2.9**: Setup Kubernetes ServiceAccount for Vault auth (Phase 3)
  - [ ] Create namespace: `external-secrets`
  - [ ] Create ServiceAccount: `external-secrets`
  - [ ] Configure Vault Kubernetes auth
- [ ] **Task 2.10**: Setup image pull secrets for Harbor (if needed)
  - [ ] Create docker-registry secrets
  - [ ] Test image pull from Harbor

### Validation of Phase 2
- [ ] All nodes are in `Ready` state
- [ ] System pods are running (coredns, metrics-server)
- [ ] Vault CA is trusted by nodes
- [ ] Harbor registry is accessible
- [x] Commit all NixOS configurations to git

### Phase 2 Deployment Steps
```bash
# 1. Start master VM and apply configuration
make k8s-master-up
make rebuild-k8s-master-switch

# 2. Wait for RKE2 server to initialize (check logs)
make k8s-master-logs

# 3. Distribute token to workers
make k8s-distribute-token

# 4. Start worker VMs and apply configurations
make k8s-workers-up
make rebuild-k8s-worker-1-switch
make rebuild-k8s-worker-2-switch
make rebuild-k8s-worker-3-switch

# 5. Verify cluster
make k8s-cluster-status

# 6. Get kubeconfig for local use
make k8s-kubeconfig
export KUBECONFIG=~/.kube/config-kss
kubectl get nodes
```

---

## Phase 3: Cluster Bootstrap with Helmfile

### Setup Helmfile Infrastructure
- [ ] **Task 3.1**: Install Helm on workstation
  - [ ] Download and install Helm binary
  - [ ] Verify helm version
- [ ] **Task 3.2**: Create Helmfile structure
  - [ ] Create directory: `helmfile/`
  - [ ] Create directory: `helmfile/values/`
  - [ ] Create file: `helmfile/bootstrap.yaml`

### Install Core Components (in order)

#### Cilium & Tetragon
- [ ] **Task 3.3**: Add Cilium Helm repository
  - [ ] `helm repo add cilium https://helm.cilium.io/`
  - [ ] `helm repo update`
- [ ] **Task 3.4**: Create Cilium values file
  - [ ] Disable default CNI (already in Helm values)
  - [ ] Configure BGP routing (for Unifi router integration)
  - [ ] Configure NetworkPolicy support
  - [ ] Create `helmfile/values/cilium.yaml`
- [ ] **Task 3.5**: Install Cilium via Helm
  - [ ] Add Cilium to `helmfile/bootstrap.yaml`
  - [ ] Run: `helmfile -f helmfile/bootstrap.yaml apply`
  - [ ] Verify Cilium pods: `kubectl get pods -n kube-system`
  - [ ] Test connectivity between pods
- [ ] **Task 3.6**: Install Tetragon
  - [ ] Create `helmfile/values/tetragon.yaml`
  - [ ] Add Tetragon to `helmfile/bootstrap.yaml`
  - [ ] Run: `helmfile -f helmfile/bootstrap.yaml apply`
  - [ ] Verify Tetragon pods: `kubectl get pods -n kube-system`

#### cert-manager
- [ ] **Task 3.7**: Add cert-manager Helm repository
  - [ ] `helm repo add jetstack https://charts.jetstack.io`
  - [ ] `helm repo update`
- [ ] **Task 3.8**: Create cert-manager values file
  - [ ] Configure Vault as PKI backend
  - [ ] Create `helmfile/values/cert-manager.yaml`
- [ ] **Task 3.9**: Install cert-manager
  - [ ] Add cert-manager to `helmfile/bootstrap.yaml`
  - [ ] Run: `helmfile -f helmfile/bootstrap.yaml apply`
  - [ ] Verify cert-manager pods: `kubectl get pods -n cert-manager`
- [ ] **Task 3.10**: Create Vault ClusterIssuer
  - [ ] Create `kustomize/base/cert-manager-issuer.yaml`
  - [ ] Configure Vault auth (Kubernetes auth method)
  - [ ] Configure PKI path in Vault
  - [ ] Apply: `kubectl apply -f kustomize/base/cert-manager-issuer.yaml`
  - [ ] Test certificate issuance

#### external-secrets
- [ ] **Task 3.11**: Add external-secrets Helm repository
  - [ ] `helm repo add external-secrets https://charts.external-secrets.io`
  - [ ] `helm repo update`
- [ ] **Task 3.12**: Create external-secrets values file
  - [ ] Configure Vault backend
  - [ ] Create `helmfile/values/external-secrets.yaml`
- [ ] **Task 3.13**: Install external-secrets
  - [ ] Add external-secrets to `helmfile/bootstrap.yaml`
  - [ ] Run: `helmfile -f helmfile/bootstrap.yaml apply`
  - [ ] Verify external-secrets pods: `kubectl get pods -n external-secrets`
- [ ] **Task 3.14**: Create Vault SecretStore
  - [ ] Create `kustomize/base/vault-secretstore.yaml`
  - [ ] Configure Vault auth (ServiceAccount JWT)
  - [ ] Apply: `kubectl apply -f kustomize/base/vault-secretstore.yaml`
  - [ ] Test secret sync from Vault

#### ArgoCD
- [ ] **Task 3.15**: Add ArgoCD Helm repository
  - [ ] `helm repo add argo https://argoproj.github.io/argo-helm`
  - [ ] `helm repo update`
- [ ] **Task 3.16**: Create ArgoCD values file
  - [ ] Configure ingress
  - [ ] Configure Git repository (SSH or HTTPS)
  - [ ] Configure notifications (optional)
  - [ ] Create `helmfile/values/argocd.yaml`
- [ ] **Task 3.17**: Install ArgoCD
  - [ ] Add ArgoCD to `helmfile/bootstrap.yaml`
  - [ ] Run: `helmfile -f helmfile/bootstrap.yaml apply`
  - [ ] Verify ArgoCD pods: `kubectl get pods -n argocd`
  - [ ] Get initial ArgoCD password: `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d`
- [ ] **Task 3.18**: Configure ArgoCD Git repository
  - [ ] Create SSH key for Git access
  - [ ] Add key to Git provider
  - [ ] Configure ArgoCD with Git repository details
  - [ ] Test ArgoCD Git sync

#### Nginx Ingress
- [ ] **Task 3.19**: Add Nginx Ingress Helm repository
  - [ ] `helm repo add nginx-stable https://helm.nginx.com/stable`
  - [ ] `helm repo update`
- [ ] **Task 3.20**: Create Nginx Ingress values file
  - [ ] Configure LoadBalancer service
  - [ ] Configure TLS passthrough
  - [ ] Create `helmfile/values/nginx-ingress.yaml`
- [ ] **Task 3.21**: Install Nginx Ingress
  - [ ] Add Nginx to `helmfile/bootstrap.yaml`
  - [ ] Run: `helmfile -f helmfile/bootstrap.yaml apply`
  - [ ] Verify Nginx pods: `kubectl get pods -n ingress-nginx`
  - [ ] Verify LoadBalancer IP is assigned

### Validation of Phase 3
- [ ] All Helmfile releases deployed successfully
- [ ] Cilium NetworkPolicies are enforced
- [ ] Tetragon is monitoring pods
- [ ] cert-manager can issue certificates from Vault
- [ ] external-secrets is syncing secrets from Vault
- [ ] ArgoCD is connected to Git repository
- [ ] Nginx Ingress LoadBalancer has external IP
- [ ] Run smoke tests: test certificate creation, secret sync, pod networking
- [ ] Commit Helmfile and values files to git

---

## Phase 4: Cluster Services via ArgoCD

### Create ArgoCD Applications

#### Longhorn
- [ ] **Task 4.1**: Create Longhorn Helm chart values
  - [ ] Configure replicas (minimum 3)
  - [ ] Configure storage pools
  - [ ] Configure backup locations (optional)
  - [ ] Create `argocd/longhorn/values.yaml`
- [ ] **Task 4.2**: Create ArgoCD Application for Longhorn
  - [ ] Create `argocd/longhorn/application.yaml`
  - [ ] Configure Helm chart source
  - [ ] Configure sync policy (auto-sync disabled for storage)
  - [ ] Apply Application
  - [ ] Verify Longhorn pods: `kubectl get pods -n longhorn-system`
- [ ] **Task 4.3**: Configure Longhorn StorageClass
  - [ ] Create default StorageClass
  - [ ] Configure replication policy
  - [ ] Test PVC creation and binding

#### Prometheus & Grafana
- [ ] **Task 4.4**: Create Prometheus Helm chart values
  - [ ] Configure scrape configs (Kubernetes API, nodes, pods)
  - [ ] Configure retention (15 days)
  - [ ] Configure PVC size (50GB)
  - [ ] Create `argocd/prometheus/values.yaml`
- [ ] **Task 4.5**: Create Grafana Helm chart values
  - [ ] Configure Prometheus as data source
  - [ ] Configure admin password (from Vault)
  - [ ] Configure dashboards (Kubernetes, application dashboards)
  - [ ] Create `argocd/grafana/values.yaml`
- [ ] **Task 4.6**: Create ArgoCD Applications
  - [ ] Create `argocd/prometheus/application.yaml`
  - [ ] Create `argocd/grafana/application.yaml`
  - [ ] Apply Applications
  - [ ] Verify pods: `kubectl get pods -n monitoring`
- [ ] **Task 4.7**: Configure Ingress for Grafana
  - [ ] Create Ingress resource for Grafana
  - [ ] Configure TLS with cert-manager
  - [ ] Test Grafana access via browser

#### Loki & Log Collection
- [ ] **Task 4.8**: Create Loki values file
  - [ ] Configure MinIO backend
  - [ ] Configure encryption (AES-256)
  - [ ] Configure retention (30 days)
  - [ ] Create `argocd/loki/values.yaml`
- [ ] **Task 4.9**: Create Promtail values file
  - [ ] Configure Loki endpoint
  - [ ] Configure pod and node log collection
  - [ ] Create `argocd/promtail/values.yaml`
- [ ] **Task 4.10**: Create ArgoCD Applications
  - [ ] Create `argocd/loki/application.yaml`
  - [ ] Create `argocd/promtail/application.yaml`
  - [ ] Apply Applications
  - [ ] Verify pods: `kubectl get pods -n logging`
- [ ] **Task 4.11**: Verify Loki log ingestion
  - [ ] Check MinIO for log storage
  - [ ] Query logs in Grafana Loki data source

#### Trivy Operator
- [ ] **Task 4.12**: Create Trivy Operator values file
  - [ ] Configure vulnerability scanner
  - [ ] Configure Harbor as registry
  - [ ] Configure severity thresholds
  - [ ] Create `argocd/trivy-operator/values.yaml`
- [ ] **Task 4.13**: Create ArgoCD Application
  - [ ] Create `argocd/trivy-operator/application.yaml`
  - [ ] Apply Application
  - [ ] Verify pods: `kubectl get pods -n trivy-system`
- [ ] **Task 4.14**: Verify vulnerability scanning
  - [ ] Deploy a test pod
  - [ ] Check for VulnerabilityReport CRD
  - [ ] View scan results

### Validation of Phase 4
- [ ] All applications deployed via ArgoCD
- [ ] Longhorn PVCs can be created and used
- [ ] Prometheus is collecting metrics
- [ ] Grafana dashboards are showing cluster metrics
- [ ] Loki is collecting logs and storing in MinIO
- [ ] Trivy Operator is scanning images
- [ ] Run end-to-end test: deploy app, verify monitoring and logging
- [ ] Commit ArgoCD application manifests to git

---

## Phase 5: Network & Service Configuration

### Unifi Router BGP Configuration
- [ ] **Task 5.1**: Enable BGP on Unifi router
  - [ ] Configure BGP autonomous system number
  - [ ] Configure Cilium to announce LoadBalancer IPs via BGP
- [ ] **Task 5.2**: Test BGP route announcement
  - [ ] Deploy a service with LoadBalancer type
  - [ ] Verify route is announced to Unifi router
  - [ ] Verify external access to service

### DNS Integration
- [ ] **Task 5.3**: Setup ExternalDNS for Unifi
  - [ ] Create ExternalDNS Helm chart values
  - [ ] Configure Unifi webhook integration
  - [ ] Create `argocd/external-dns/values.yaml`
- [ ] **Task 5.4**: Deploy ExternalDNS
  - [ ] Create `argocd/external-dns/application.yaml`
  - [ ] Apply Application
  - [ ] Verify pods: `kubectl get pods -n external-dns`
- [ ] **Task 5.5**: Test ExternalDNS
  - [ ] Deploy service with ExternalDNS annotation
  - [ ] Verify DNS record is created in Unifi
  - [ ] Verify DNS resolution

### Wildcard Certificate Setup
- [ ] **Task 5.6**: Create Certificate resource for wildcard
  - [ ] Create `kustomize/base/wildcard-cert.yaml`
  - [ ] Configure CloudFlare DNS01 solver
  - [ ] Configure Let's Encrypt issuer (staging first)
  - [ ] Apply Certificate
  - [ ] Verify certificate is issued
- [ ] **Task 5.7**: Switch to Let's Encrypt production
  - [ ] Update ClusterIssuer to production endpoint
  - [ ] Delete staging certificate
  - [ ] Recreate certificate with production issuer
  - [ ] Verify production certificate is issued

### Validation of Phase 5
- [ ] Services with LoadBalancer type receive external IPs
- [ ] BGP announces routes to Unifi router
- [ ] Services are accessible via external IPs
- [ ] ExternalDNS creates DNS records in Unifi
- [ ] Wildcard certificate is issued by Let's Encrypt
- [ ] Services are accessible via HTTPS with valid certificates

---

## Phase 6: Backup & Recovery

### Backup Strategy Implementation
- [ ] **Task 6.1**: Setup Velero for cluster backups
  - [ ] Create Velero Helm chart values
  - [ ] Configure MinIO as backup backend
  - [ ] Create `argocd/velero/values.yaml`
- [ ] **Task 6.2**: Deploy Velero
  - [ ] Create `argocd/velero/application.yaml`
  - [ ] Apply Application
  - [ ] Verify Velero pods: `kubectl get pods -n velero`
- [ ] **Task 6.3**: Configure backup schedules
  - [ ] Create daily backup schedule
  - [ ] Configure retention policy (30 days)
  - [ ] Test backup creation
  - [ ] Verify backups in MinIO
- [ ] **Task 6.4**: Test recovery procedure
  - [ ] Delete test namespace
  - [ ] Restore from backup
  - [ ] Verify restoration

### Vault Backup
- [ ] **Task 6.5**: Configure Vault backup
  - [ ] Backup unseal keys (store in secure location)
  - [ ] Configure Raft snapshot backups (if using Raft)
  - [ ] Store backups in MinIO (encrypted)
  - [ ] Document recovery procedure

### Validation of Phase 6
- [ ] Velero backups are created automatically
- [ ] Backups are stored in MinIO
- [ ] Recovery from backup works correctly
- [ ] Vault backups are secure and accessible
- [ ] Document recovery procedures in repository

---

## Phase 7: Monitoring & Alerting

### Alerting Rules
- [ ] **Task 7.1**: Create Prometheus alert rules
  - [ ] Configure alerts for high CPU/memory
  - [ ] Configure alerts for pod restarts
  - [ ] Configure alerts for persistent volume usage
  - [ ] Create `kustomize/base/prometheus-rules.yaml`
- [ ] **Task 7.2**: Configure Alertmanager
  - [ ] Setup notification channels (Slack, email, etc.)
  - [ ] Configure alert routing
  - [ ] Test alert delivery

### Logging Strategy
- [ ] **Task 7.3**: Configure Loki retention policies
  - [ ] Test log retention and cleanup
  - [ ] Monitor Loki storage usage
- [ ] **Task 7.4**: Setup log-based alerts
  - [ ] Configure alerts for error logs
  - [ ] Configure alerts for warning logs
  - [ ] Test alert triggering

### Validation of Phase 7
- [ ] Prometheus alerts are firing correctly
- [ ] Alertmanager delivers notifications
- [ ] Loki logs are retained per policy
- [ ] Log-based alerts work correctly

---

## Phase 8: Security Hardening

### Network Policies
- [ ] **Task 8.1**: Create Cilium NetworkPolicies
  - [ ] Deny-all default policy
  - [ ] Allow policies per application
  - [ ] Create `kustomize/base/network-policies.yaml`
  - [ ] Apply policies and test
- [ ] **Task 8.2**: Configure pod security standards
  - [ ] Configure restricted pod security standard
  - [ ] Apply to all namespaces
  - [ ] Test pod creation with different security contexts

### RBAC Configuration
- [ ] **Task 8.3**: Create RBAC roles and bindings
  - [ ] Create least-privilege roles
  - [ ] Bind roles to ServiceAccounts
  - [ ] Create `kustomize/base/rbac.yaml`
- [ ] **Task 8.4**: Configure API audit logging
  - [ ] Enable kube-apiserver audit logging
  - [ ] Configure audit policy (log sensitive operations)
  - [ ] Test audit log generation

### Image Security
- [ ] **Task 8.5**: Configure image pull policies
  - [ ] Set imagePullPolicy: Always
  - [ ] Configure image signature verification (if available)
- [ ] **Task 8.6**: Regular vulnerability scanning
  - [ ] Ensure Trivy Operator is scanning all images
  - [ ] Create alerting for critical vulnerabilities
  - [ ] Document remediation process

### Validation of Phase 8
- [ ] Network policies are enforced
- [ ] RBAC prevents unauthorized access
- [ ] Audit logs are collected
- [ ] Vulnerability scanning is active
- [ ] All security policies are documented

---

## Phase 9: CI/CD & Automation

### Renovatebot Configuration
- [ ] **Task 9.1**: Create .renovaterc.json
  - [ ] Configure update schedule
  - [ ] Group dependency updates
  - [ ] Configure auto-merge for patches
  - [ ] Configure PR prefixes and labels
- [ ] **Task 9.2**: Setup Renovate bot
  - [ ] Install Renovate bot on repository
  - [ ] Configure bot permissions
  - [ ] Test bot on test branch
- [ ] **Task 9.3**: Configure automated testing
  - [ ] Create GitHub Actions for Trivy scans
  - [ ] Create GitHub Actions for Helm lint
  - [ ] Create GitHub Actions for manifest validation

### Trivy Configuration
- [ ] **Task 9.4**: Create .trivy.yaml
  - [ ] Configure scanning targets
  - [ ] Configure severity thresholds
  - [ ] Configure output formats
- [ ] **Task 9.5**: Setup Trivy scanning
  - [ ] Configure GitHub Actions for Trivy scans
  - [ ] Scan container images
  - [ ] Scan Kubernetes manifests
  - [ ] Scan Helm charts
- [ ] **Task 9.6**: Implement remediation workflow
  - [ ] Triage critical findings
  - [ ] Track remediation in issues
  - [ ] Document known vulnerabilities

### Validation of Phase 9
- [ ] Renovate creates PRs for updates
- [ ] Trivy scans find vulnerabilities
- [ ] GitHub Actions workflows pass
- [ ] Automated testing works correctly

---

## Phase 10: Documentation & Runbooks

### Documentation
- [ ] **Task 10.1**: Create operational runbooks
  - [ ] How to scale Kubernetes cluster
  - [ ] How to backup and restore
  - [ ] How to upgrade components
  - [ ] How to troubleshoot common issues
- [ ] **Task 10.2**: Create troubleshooting guide
  - [ ] Common errors and solutions
  - [ ] Debug procedures
  - [ ] Log analysis examples
- [ ] **Task 10.3**: Create capacity planning guide
  - [ ] Current resource allocation
  - [ ] Growth projections
  - [ ] Upgrade paths

### Training
- [ ] **Task 10.4**: Document manual procedures
  - [ ] How to access cluster
  - [ ] How to deploy applications
  - [ ] How to access logs and metrics
- [ ] **Task 10.5**: Create runbooks for on-call
  - [ ] Alert response procedures
  - [ ] Escalation paths
  - [ ] Contact information

### Validation of Phase 10
- [ ] All documentation is current and accurate
- [ ] Runbooks can be followed by operators
- [ ] Training materials are comprehensive

---

## Completion Checklist

### Infrastructure
- [ ] All VMs are created and running
- [ ] Supporting services (Vault, Harbor, MinIO, NFS) are operational
- [ ] Kubernetes cluster is fully functional
- [ ] All nodes are in Ready state

### Applications
- [ ] All core services deployed via Helmfile
- [ ] All additional services deployed via ArgoCD
- [ ] All services are accessible and functional
- [ ] Monitoring and logging are working

### Security
- [ ] Vault is properly initialized and secured
- [ ] All secrets are in Vault
- [ ] TLS certificates are valid and renewed automatically
- [ ] Network policies are enforced
- [ ] RBAC is properly configured
- [ ] Vulnerability scanning is active

### Operations
- [ ] Backups are created and tested
- [ ] Monitoring and alerting are working
- [ ] Documentation is complete
- [ ] Runbooks are tested

### Validation
- [ ] All smoke tests pass
- [ ] End-to-end functionality is verified
- [ ] Performance targets are met
- [ ] Security policies are enforced
- [ ] All components are properly monitored

---

## Next Steps After Completion

1. **Expand Kubernetes Cluster**: Add more worker nodes as needed
2. **Migrate Workloads**: Move applications to this infrastructure
3. **Implement Advanced Features**:
   - Multi-cluster setup with Cilium ClusterMesh
   - Service mesh (Cilium or Istio)
   - Policy as code (OPA/Gatekeeper)
   - Chaos engineering (Litmus, Gremlin)
4. **Production Hardening**:
   - Replace single supporting-systems VM with HA setup
   - Implement disaster recovery (cross-site replication)
   - Setup production-grade monitoring and alerting
   - Implement security scanning in CI/CD

---

## Notes

- Each task should be committed to git with a clear commit message
- Test thoroughly at each phase before proceeding to the next
- Document any deviations from this plan
- Keep this TODO updated as you progress
- Use branches for experimental work, merge to main only after validation
