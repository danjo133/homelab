# Kubernetes Homelab - Infrastructure as Code

A modern, secure Kubernetes setup designed for homelab experimentation with a path to production infrastructure.

## Quick Start

### Prerequisites
- Arch Linux workstation with 48GB+ RAM
- VirtualBox installed
- Vagrant installed
- Nix/NixOS environment (optional, uses flake.nix)

### Setup

1. **Review documentation**:
   ```bash
   cat iac/docs/ARCHITECTURE.md
   cat iac/docs/SPEC-KIT.md
   cat iac/docs/TODO.md
   ```

2. **Setup development environment**:
   ```bash
   # Using Nix flakes
   nix flake update
   nix develop
   
   # Or manually install tools:
   make install-tools
   ```

3. **Start infrastructure**:
   ```bash
   make up           # Bring up VMs
   make provision    # Provision with NixOS
   ```

4. **Access cluster**:
   ```bash
   make k8s-config   # Get kubeconfig
   make k8s-status   # Check cluster health
   ```

## Available Commands

```bash
make help           # Show all available commands
make up             # Bring up all VMs
make down           # Stop VMs (without destroying)
make provision      # Provision VMs with NixOS
make reset          # Destroy and recreate infrastructure
make validate       # Validate configurations
make test           # Run smoke tests
make docs           # View documentation
```

## Project Structure

```
kss/
├── iac/                          # Infrastructure as Code
│   ├── docs/
│   │   ├── ARCHITECTURE.md        # System architecture
│   │   ├── SPEC-KIT.md            # Detailed specifications
│   │   └── TODO.md                # Step-by-step implementation plan
│   ├── provision/
│   │   ├── nix/                   # NixOS configurations
│   │   │   ├── supporting-systems/
│   │   │   ├── k8s-master/
│   │   │   └── k8s-worker/
│   │   └── scripts/               # Provisioning scripts
│   ├── helmfile/                  # Helm chart definitions
│   │   ├── bootstrap.yaml         # Initial cluster setup
│   │   └── values/                # Helm values files
│   └── kustomize/                 # Kubernetes customization
│       ├── base/                  # Base configurations
│       └── overlays/              # Environment overlays
├── iac_ansible/                   # Ansible for VM setup
│   ├── Vagrantfile                # VM definitions
│   └── provision/                 # Ansible playbooks
├── Makefile                       # Build/deployment tasks
├── flake.nix                      # Nix development environment
├── .renovaterc.json               # Dependency management
├── .trivy.yaml                    # Vulnerability scanning
└── README.md                      # This file
```

## Architecture Overview

### Networking
- **Base Domain**: `support.example.com`
- **Root Domain**: `example.com` (Cloudflare)
- **Subdomain**: `example.com` (Unifi)

### Infrastructure
- **Supporting Systems VM**: Vault, Harbor, MinIO, NFS
- **Kubernetes Cluster**: 1 master + 3 workers (RKE2 on NixOS)
- **CNI**: Cilium with Tetragon hardening
- **Storage**: Longhorn, MinIO, NFS
- **Observability**: Prometheus, Grafana, Loki

### Key Components
- **Vault**: PKI and secrets management
- **Harbor**: Private container registry with proxy caches
- **MinIO**: S3-compatible object storage
- **RKE2**: Kubernetes distribution
- **ArgoCD**: GitOps continuous deployment
- **cert-manager**: Automated certificate management
- **external-secrets**: Secret synchronization from Vault

## Implementation Phases

1. **Phase 0**: Pre-infrastructure setup and network configuration
2. **Phase 1**: Supporting infrastructure VM (Vault, Harbor, MinIO, NFS)
3. **Phase 2**: Kubernetes cluster VMs and RKE2 installation
4. **Phase 3**: Cluster bootstrap with Helmfile
5. **Phase 4**: Deploy services via ArgoCD
6. **Phase 5**: Network and service configuration
7. **Phase 6**: Backup and recovery
8. **Phase 7**: Monitoring and alerting
9. **Phase 8**: Security hardening
10. **Phase 9**: CI/CD and automation
11. **Phase 10**: Documentation and runbooks

See [TODO.md](iac/docs/TODO.md) for detailed step-by-step implementation guide.

## Security Features

- ✅ Vault for centralized secret management
- ✅ Cilium NetworkPolicies for pod security
- ✅ Tetragon for runtime pod hardening
- ✅ cert-manager with Let's Encrypt for TLS
- ✅ Trivy operator for vulnerability scanning
- ✅ Pod security standards (restricted)
- ✅ RBAC with least-privilege access
- ✅ Kubernetes audit logging

## Scalability Path

Current setup can scale from:
- Single workstation → Multiple hypervisors
- Single supporting-systems VM → Distributed services
- 4-node K8s cluster → Larger production cluster
- Local storage → Distributed NFS/MinIO

## Dependencies

### System Requirements
- Linux (Arch Linux recommended)
- VirtualBox
- 48GB+ RAM
- 200GB+ storage

### Tools
- Vagrant
- Helm
- kubectl
- Kustomize
- Helmfile
- Nix/NixOS (optional)

### Services
- Git repository (GitHub, GitLab, Gitea)
- Cloudflare DNS (for wildcard cert DNS01)
- Unifi router (for BGP and DNS)

## Automation

### Renovatebot
Automatically creates PRs for dependency updates:
- Kubernetes and RKE2 updates
- Helm chart updates
- Container image updates
- NixOS package updates

Configure in [.renovaterc.json](.renovaterc.json)

### Trivy Scanning
Vulnerability scanning for:
- Container images
- Kubernetes manifests
- Source code

Configure in [.trivy.yaml](.trivy.yaml)

## Monitoring

- **Prometheus**: Metrics collection and alerting
- **Grafana**: Visualization dashboards
- **Loki**: Log aggregation (stored in MinIO)
- **Trivy Operator**: Container image vulnerability scanning
- **Tetragon**: Runtime security monitoring

## Troubleshooting

### Check VM Status
```bash
cd iac_ansible
vagrant status
vagrant ssh k8s-master
```

### Check Kubernetes
```bash
kubectl get nodes
kubectl get pods -A
kubectl logs -n kube-system <pod-name>
```

### Check Services
```bash
# Vault
curl -k https://trust.support.example.com:8200/v1/sys/health

# Harbor
curl -k https://artifacts.support.example.com

# MinIO
curl -k https://minio.example.com:9000
```

## Contributing

1. Create a feature branch
2. Make changes and test with `make validate`
3. Commit with semantic messages: `chore(docs): update README`
4. Run `make test` before pushing
5. Create pull request

## License

See LICENSE file

## References

- [RKE2 Documentation](https://docs.rke2.io/)
- [Cilium Documentation](https://docs.cilium.io/)
- [Vault Documentation](https://www.vaultproject.io/docs)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

## Support

For issues, questions, or suggestions, please:
1. Check [TODO.md](iac/docs/TODO.md) for implementation status
2. Review [ARCHITECTURE.md](iac/docs/ARCHITECTURE.md) for design decisions
3. Check existing issues and discussions
4. Create a new issue with detailed information

---

**Last Updated**: January 1, 2026
**Status**: Initial scaffolding and documentation complete - Ready for Phase 0 setup
