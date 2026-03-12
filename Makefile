.PHONY: help up provision down reset clean lint test validate sync-support rebuild-support rebuild-support-switch generate-network-config bootstrap-vault-k8s apply-vault-auth configure-vault-k8s-auth k8s-destroy k8s-destroy-master k8s-destroy-workers k8s-recreate k8s-clean-state k8s-deploy-default k8s-deploy-bgp-simple k8s-deploy-gateway-bgp k8s-deploy-base-resources k8s-deploy-vault-auth k8s-deploy-secrets
.DEFAULT_GOAL := help

# Color output
BLUE := \033[0;34m
GREEN := \033[0;32m
RED := \033[0;31m
NC := \033[0m # No Color

# Paths (local - on workstation, files are sshfs-mounted from iter)
VAGRANT_DIR := $(shell pwd)/iac
HELMFILE_DIR := $(shell pwd)/iac/helmfile
KUSTOMIZE_DIR := $(shell pwd)/iac/kustomize
DOCS_DIR := $(shell pwd)/iac/docs
SUPPORT_NIX_DIR := $(shell pwd)/iac/provision/nix/supporting-systems

# Remote execution configuration
# Vagrant/libvirt runs on iter, code is at ~/dev/homelab there
REMOTE_HOST := iter
REMOTE_PROJECT_DIR := ~/dev/homelab
REMOTE_VAGRANT_DIR := $(REMOTE_PROJECT_DIR)/iac

# SSH key for direct VM access
VAGRANT_SSH_KEY := ~/.vagrant.d/ecdsa_private_key

# VM IPs - using fixed IPs from Unifi DHCP static leases
# See CLAUDE.md DNS Configuration section for MAC/IP mapping
SUPPORT_VM_IP ?= 10.69.50.10
K8S_MASTER_IP ?= 10.69.50.20
K8S_WORKER_1_IP ?= 10.69.50.31
K8S_WORKER_2_IP ?= 10.69.50.32
K8S_WORKER_3_IP ?= 10.69.50.33

# Help target
help:
	@echo "$(BLUE)Kubernetes Homelab Infrastructure - Make Commands$(NC)"
	@echo ""
	@echo "$(GREEN)VM Management (runs on iter):$(NC)"
	@echo "  make up                Start all Vagrant VMs"
	@echo "  make down              Stop all Vagrant VMs"
	@echo "  make status            Show Vagrant VM status"
	@echo "  make reset             Destroy and recreate all VMs"
	@echo "  make clean             Clean up Vagrant artifacts"
	@echo ""
	@echo "$(GREEN)Support VM:$(NC)"
	@echo "  make sync-support          Sync NixOS config to support VM"
	@echo "  make rebuild-support       Rebuild support VM (test mode)"
	@echo "  make rebuild-support-switch Rebuild and switch permanently"
	@echo "  make support-status        Check service status on support VM"
	@echo "  make support-logs          Show recent logs from support VM"
	@echo "  make vagrant-ssh-support   SSH into support VM"
	@echo ""
	@echo "$(GREEN)Kubernetes Cluster:$(NC)"
	@echo "  make k8s-destroy           Destroy all k8s VMs"
	@echo "  make k8s-destroy-master    Destroy k8s-master VM only"
	@echo "  make k8s-destroy-workers   Destroy all k8s-worker VMs"
	@echo "  make k8s-recreate          Destroy and recreate all k8s VMs"
	@echo "  make k8s-master-up         Start k8s-master VM"
	@echo "  make k8s-workers-up        Start all k8s-worker VMs"
	@echo "  make sync-k8s-master       Sync NixOS config to k8s-master"
	@echo "  make rebuild-k8s-master    Rebuild k8s-master (test mode)"
	@echo "  make rebuild-k8s-master-switch  Rebuild and switch permanently"
	@echo "  make sync-k8s-worker-{1,2,3}    Sync config to worker"
	@echo "  make rebuild-k8s-worker-{1,2,3} Rebuild worker (test mode)"
	@echo "  make k8s-cluster-status    Check cluster nodes and pods"
	@echo "  make k8s-get-token         Show RKE2 join token"
	@echo "  make k8s-distribute-token  Copy join token to workers"
	@echo "  make k8s-kubeconfig        Fetch kubeconfig locally"
	@echo "  make k8s-master-status     Check k8s-master services"
	@echo "  make k8s-master-logs       Show RKE2 server logs"
	@echo "  make vagrant-ssh-k8s-master SSH into k8s-master"
	@echo "  make vagrant-ssh-k8s-worker-{1,2,3} SSH into worker"
	@echo ""
	@echo "$(GREEN)Deployment (requires KUBECONFIG):$(NC)"
	@echo "  make k8s-deploy-default      Full deploy: MetalLB L2 + nginx-ingress + secrets (no Cilium)"
	@echo "  make k8s-deploy-bgp-simple   Full deploy: vault-auth + helmfile bgp-simple + secrets + Cilium CRDs"
	@echo "  make k8s-deploy-gateway-bgp  Full deploy: vault-auth + helmfile gateway-bgp + secrets + Gateway CRDs"
	@echo "  make k8s-deploy-vault-auth   Configure vault-auth SA and update Vault k8s auth"
	@echo "  make k8s-deploy-secrets      Apply ClusterSecretStore + ExternalSecrets + cert-manager"
	@echo "  make k8s-deploy-base-resources All kustomize base resources (vault-auth + secrets + cert-manager)"
	@echo ""
	@echo "$(GREEN)Vault Key Management:$(NC)"
	@echo "  make vault-backup-keys     Backup Vault keys to local file"
	@echo "  make vault-restore-keys    Restore Vault keys from backup"
	@echo "  make vault-show-token      Show Vault root token"
	@echo ""
	@echo "$(GREEN)Cilium Debugging:$(NC)"
	@echo "  make cilium-status     Check Cilium pod and agent status"
	@echo "  make cilium-health     Check Cilium cluster connectivity"
	@echo "  make cilium-endpoints  List Cilium endpoints"
	@echo "  make cilium-services   Show Cilium service map and BPF LB"
	@echo "  make cilium-config     Show Cilium configuration"
	@echo "  make cilium-bpf        Show BPF program attachments"
	@echo "  make cilium-logs       Show Cilium agent logs"
	@echo "  make cilium-restart    Restart all Cilium pods"
	@echo ""
	@echo "$(GREEN)Network Debugging:$(NC)"
	@echo "  make net-debug-master  Show network info on k8s-master"
	@echo "  make net-debug-worker1 Show network info on k8s-worker-1"
	@echo "  make net-test-clusterip Test ClusterIP from each node"
	@echo "  make k8s-diag          Quick cluster diagnostics"
	@echo "  make k8s-rebuild-all   Sync and rebuild all k8s nodes"
	@echo ""
	@echo "$(GREEN)Network Configuration:$(NC)"
	@echo "  make generate-network-config  Generate Cilium CRDs and FRR config"
	@echo ""
	@echo "$(GREEN)Vault & Secrets:$(NC)"
	@echo "  make bootstrap-vault-k8s      Configure Vault for k8s external-secrets"
	@echo "  make apply-vault-auth         Apply vault-auth kustomize resources"
	@echo "  make configure-vault-k8s-auth Configure Vault with k8s token reviewer"
	@echo ""
	@echo "$(GREEN)Validation & Testing:$(NC)"
	@echo "  make validate          Validate Helm and Kustomize manifests"
	@echo "  make lint              Lint documentation and configurations"
	@echo "  make test              Run smoke tests"
	@echo ""

# ============================================================================
# VM Management (all run on iter via SSH)
# ============================================================================

up: ## Start all Vagrant VMs
	@echo "$(BLUE)Starting all Vagrant VMs...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant up"
	@echo "$(GREEN)VMs started!$(NC)"

down: ## Stop all VMs without destroying
	@echo "$(BLUE)Stopping Vagrant VMs...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant halt"
	@echo "$(GREEN)VMs stopped!$(NC)"

status: ## Show Vagrant VM status
	@echo "$(BLUE)Vagrant VM Status:$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant status"

reset: ## Destroy and recreate all VMs (full reset)
	@echo "$(RED)Resetting infrastructure...$(NC)"
	@read -p "Are you sure? This will destroy all VMs. [y/N] " -n 1 -r; \
	echo ""; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant destroy -f"; \
		ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant up"; \
		echo "$(GREEN)Infrastructure reset complete!$(NC)"; \
	else \
		echo "$(BLUE)Reset cancelled$(NC)"; \
	fi

clean: ## Clean up Vagrant artifacts
	@echo "$(BLUE)Cleaning up...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant destroy -f"
	@rm -rf .kubeconfig
	@echo "$(GREEN)Cleanup complete!$(NC)"

# ============================================================================
# Support VM NixOS Configuration Management
# ============================================================================

sync-support: ## Sync NixOS configuration to support VM
	@echo "$(BLUE)Syncing NixOS config to support VM ($(SUPPORT_VM_IP))...$(NC)"
	@ssh $(REMOTE_HOST) "rsync -avz --delete \
		-e 'ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY)' \
		$(REMOTE_PROJECT_DIR)/iac/provision/nix/supporting-systems/ \
		vagrant@$(SUPPORT_VM_IP):/tmp/nix-config/supporting-systems/"
	@ssh $(REMOTE_HOST) "rsync -avz \
		-e 'ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY)' \
		$(REMOTE_PROJECT_DIR)/iac/provision/nix/common/ \
		vagrant@$(SUPPORT_VM_IP):/tmp/nix-config/common/"
	@echo "$(BLUE)Syncing sops age key to support VM...$(NC)"
	@ssh $(REMOTE_HOST) "ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY) vagrant@$(SUPPORT_VM_IP) \
		'sudo mkdir -p /etc/sops/keys && sudo chmod 700 /etc/sops/keys'"
	@ssh $(REMOTE_HOST) "cat ~/.vagrant.d/sops_age_keys.txt | ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY) vagrant@$(SUPPORT_VM_IP) \
		'sudo tee /etc/sops/keys/age-keys.txt > /dev/null && sudo chmod 600 /etc/sops/keys/age-keys.txt'"
	@echo "$(GREEN)Config synced to /tmp/nix-config/ on support VM$(NC)"

rebuild-support: sync-support ## Rebuild support VM NixOS config (test mode)
	@echo "$(BLUE)Rebuilding NixOS configuration (test mode)...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh support -c \
		'sudo nixos-rebuild test -I nixos-config=/tmp/nix-config/supporting-systems/configuration.nix'"
	@echo "$(GREEN)Configuration applied (test mode - not permanent)$(NC)"

rebuild-support-switch: sync-support ## Rebuild and switch support VM NixOS config permanently
	@echo "$(BLUE)Rebuilding NixOS configuration (switch mode)...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh support -c \
		'sudo nixos-rebuild switch -I nixos-config=/tmp/nix-config/supporting-systems/configuration.nix'"
	@echo "$(GREEN)Configuration applied permanently$(NC)"

support-status: ## Check status of services on support VM
	@echo "$(BLUE)Support VM Service Status:$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh support -c \
		'systemctl status nginx vault minio nfs-server docker --no-pager'" || true

support-logs: ## Show recent logs from support VM
	@echo "$(BLUE)Support VM Logs:$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh support -c \
		'journalctl -n 50 --no-pager'"

vagrant-ssh-support: ## SSH into support VM (via iter)
	@ssh -t $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh support"

# ============================================================================
# Vault Key Management
# ============================================================================

VAULT_KEYS_BACKUP := $(shell pwd)/iac/.vault-keys-backup.json

vault-backup-keys: ## Backup Vault unseal keys to local file
	@echo "$(BLUE)Backing up Vault keys...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh support -c \
		'sudo cat /var/lib/vault/init-keys.json'" > $(VAULT_KEYS_BACKUP)
	@chmod 600 $(VAULT_KEYS_BACKUP)
	@echo "$(GREEN)Vault keys backed up to $(VAULT_KEYS_BACKUP)$(NC)"
	@echo "$(RED)WARNING: Keep this file secure! It contains the Vault root token and unseal key.$(NC)"

vault-restore-keys: ## Restore Vault unseal keys from backup
	@if [ ! -f "$(VAULT_KEYS_BACKUP)" ]; then \
		echo "$(RED)ERROR: No backup file found at $(VAULT_KEYS_BACKUP)$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Restoring Vault keys...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh support -c \
		'sudo mkdir -p /var/lib/vault && sudo tee /var/lib/vault/init-keys.json > /dev/null && sudo chmod 600 /var/lib/vault/init-keys.json && sudo chown vault:vault /var/lib/vault/init-keys.json'" < $(VAULT_KEYS_BACKUP)
	@echo "$(GREEN)Vault keys restored. Restart vault-auto-init to unseal:$(NC)"
	@echo "  ssh $(REMOTE_HOST) 'cd $(REMOTE_VAGRANT_DIR) && vagrant ssh support -c \"sudo systemctl restart vault-auto-init\"'"

vault-show-token: ## Show Vault root token (requires backup)
	@if [ ! -f "$(VAULT_KEYS_BACKUP)" ]; then \
		echo "$(RED)ERROR: No backup file found. Run 'make vault-backup-keys' first.$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Vault Root Token:$(NC)"
	@jq -r '.root_token' $(VAULT_KEYS_BACKUP)

vault-token: ## Output just the Vault root token (for scripting)
	@jq -r '.root_token' $(VAULT_KEYS_BACKUP) 2>/dev/null || echo ""

# ============================================================================
# Kubernetes Cluster Management
# ============================================================================

K8S_MASTER_NIX_DIR := $(shell pwd)/iac/provision/nix/k8s-master
K8S_WORKER_NIX_DIR := $(shell pwd)/iac/provision/nix/k8s-worker

# K8s Cluster Lifecycle
k8s-destroy: ## Destroy all k8s VMs (master + workers)
	@echo "$(RED)Destroying all Kubernetes VMs...$(NC)"
	@read -p "Are you sure? This will destroy k8s-master and all workers. [y/N] " -n 1 -r; \
	echo ""; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant destroy -f k8s-master k8s-worker-1 k8s-worker-2 k8s-worker-3"; \
		echo "$(GREEN)All k8s VMs destroyed$(NC)"; \
	else \
		echo "$(BLUE)Destroy cancelled$(NC)"; \
	fi

k8s-destroy-master: ## Destroy k8s-master VM only
	@echo "$(RED)Destroying k8s-master VM...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant destroy -f k8s-master"
	@echo "$(GREEN)k8s-master destroyed$(NC)"

k8s-destroy-workers: ## Destroy all k8s-worker VMs
	@echo "$(RED)Destroying all k8s-worker VMs...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant destroy -f k8s-worker-1 k8s-worker-2 k8s-worker-3"
	@echo "$(GREEN)All k8s-worker VMs destroyed$(NC)"

k8s-clean-state: ## Wipe RKE2 state on all k8s nodes (for re-bootstrap without VM destroy)
	@echo "$(RED)Wiping RKE2 state on all k8s nodes...$(NC)"
	@read -p "Are you sure? This removes all RKE2 data. [y/N] " -n 1 -r; \
	echo ""; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		echo "Stopping RKE2 on master ($(K8S_MASTER_IP))..."; \
		ssh $(REMOTE_HOST) "ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY) vagrant@$(K8S_MASTER_IP) 'sudo /opt/rke2/bin/rke2-killall.sh 2>/dev/null || sudo systemctl stop rke2-server 2>/dev/null || true; sudo rm -rf /var/lib/rancher/rke2/server /var/lib/rancher/rke2/agent /etc/rancher/node /etc/rancher/rke2/.token-configured /var/lib/rancher/rke2/.installed'" || true; \
		echo "Stopping RKE2 on worker-1 ($(K8S_WORKER_1_IP))..."; \
		ssh $(REMOTE_HOST) "ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY) vagrant@$(K8S_WORKER_1_IP) 'sudo /opt/rke2/bin/rke2-killall.sh 2>/dev/null || sudo systemctl stop rke2-agent 2>/dev/null || true; sudo rm -rf /var/lib/rancher/rke2/agent /etc/rancher/node /etc/rancher/rke2/config.yaml /etc/rancher/rke2/.token-configured /var/lib/rancher/rke2/.installed /var/lib/rancher/rke2/shared-token'" || true; \
		echo "Stopping RKE2 on worker-2 ($(K8S_WORKER_2_IP))..."; \
		ssh $(REMOTE_HOST) "ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY) vagrant@$(K8S_WORKER_2_IP) 'sudo /opt/rke2/bin/rke2-killall.sh 2>/dev/null || sudo systemctl stop rke2-agent 2>/dev/null || true; sudo rm -rf /var/lib/rancher/rke2/agent /etc/rancher/node /etc/rancher/rke2/config.yaml /etc/rancher/rke2/.token-configured /var/lib/rancher/rke2/.installed /var/lib/rancher/rke2/shared-token'" || true; \
		echo "Stopping RKE2 on worker-3 ($(K8S_WORKER_3_IP))..."; \
		ssh $(REMOTE_HOST) "ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY) vagrant@$(K8S_WORKER_3_IP) 'sudo /opt/rke2/bin/rke2-killall.sh 2>/dev/null || sudo systemctl stop rke2-agent 2>/dev/null || true; sudo rm -rf /var/lib/rancher/rke2/agent /etc/rancher/node /etc/rancher/rke2/config.yaml /etc/rancher/rke2/.token-configured /var/lib/rancher/rke2/.installed /var/lib/rancher/rke2/shared-token'" || true; \
		echo "$(GREEN)RKE2 state wiped. Run 'make k8s-rebuild-all' to re-bootstrap.$(NC)"; \
	else \
		echo "$(BLUE)Clean cancelled$(NC)"; \
	fi

k8s-recreate: ## Destroy and recreate all k8s VMs (clean slate)
	@echo "$(RED)Recreating all Kubernetes VMs (destroy + create)...$(NC)"
	@read -p "Are you sure? This will destroy and recreate all k8s VMs. [y/N] " -n 1 -r; \
	echo ""; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant destroy -f k8s-master k8s-worker-1 k8s-worker-2 k8s-worker-3" || true; \
		ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant up k8s-master k8s-worker-1 k8s-worker-2 k8s-worker-3"; \
		echo "$(GREEN)All k8s VMs recreated$(NC)"; \
	else \
		echo "$(BLUE)Recreate cancelled$(NC)"; \
	fi

# K8s Master VM management
k8s-master-up: ## Start k8s-master VM
	@echo "$(BLUE)Starting k8s-master VM...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant up k8s-master"
	@echo "$(GREEN)k8s-master VM started$(NC)"

sync-k8s-master: ## Sync NixOS configuration to k8s-master VM
	@echo "$(BLUE)Syncing NixOS config to k8s-master ($(K8S_MASTER_IP))...$(NC)"
	@ssh $(REMOTE_HOST) "rsync -avz \
		-e 'ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY)' \
		$(REMOTE_PROJECT_DIR)/iac/provision/nix/k8s-master/ \
		vagrant@$(K8S_MASTER_IP):/tmp/nix-config/"
	@ssh $(REMOTE_HOST) "rsync -avz \
		-e 'ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY)' \
		$(REMOTE_PROJECT_DIR)/iac/provision/nix/k8s-common/ \
		vagrant@$(K8S_MASTER_IP):/tmp/nix-config/k8s-common/"
	@ssh $(REMOTE_HOST) "rsync -avz \
		-e 'ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY)' \
		$(REMOTE_PROJECT_DIR)/iac/provision/nix/common/ \
		vagrant@$(K8S_MASTER_IP):/tmp/nix-config/common/"
	@echo "$(GREEN)Config synced to k8s-master:/tmp/nix-config/$(NC)"

rebuild-k8s-master: sync-k8s-master ## Rebuild k8s-master NixOS config (test mode)
	@echo "$(BLUE)Rebuilding k8s-master NixOS configuration (test mode)...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-master -c \
		'sudo nixos-rebuild test -I nixos-config=/tmp/nix-config/configuration.nix'"
	@echo "$(GREEN)Configuration applied (test mode - not permanent)$(NC)"

rebuild-k8s-master-switch: sync-k8s-master ## Rebuild and switch k8s-master NixOS config permanently
	@echo "$(BLUE)Rebuilding k8s-master NixOS configuration (switch mode)...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-master -c \
		'sudo nixos-rebuild switch -I nixos-config=/tmp/nix-config/configuration.nix'"
	@echo "$(GREEN)Configuration applied permanently$(NC)"

# K8s Worker VMs management
k8s-workers-up: ## Start all k8s-worker VMs
	@echo "$(BLUE)Starting k8s-worker VMs...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant up k8s-worker-1 k8s-worker-2 k8s-worker-3"
	@echo "$(GREEN)k8s-worker VMs started$(NC)"

# Worker 1
sync-k8s-worker-1: ## Sync NixOS configuration to k8s-worker-1 VM
	@echo "$(BLUE)Syncing NixOS config to k8s-worker-1 ($(K8S_WORKER_1_IP))...$(NC)"
	@ssh $(REMOTE_HOST) "ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY) vagrant@$(K8S_WORKER_1_IP) 'mkdir -p /tmp/nix-config'"
	@ssh $(REMOTE_HOST) "rsync -avz \
		-e 'ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY)' \
		$(REMOTE_PROJECT_DIR)/iac/provision/nix/k8s-worker/ \
		vagrant@$(K8S_WORKER_1_IP):/tmp/nix-config/k8s-worker/"
	@ssh $(REMOTE_HOST) "rsync -avz \
		-e 'ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY)' \
		$(REMOTE_PROJECT_DIR)/iac/provision/nix/k8s-worker-1/ \
		vagrant@$(K8S_WORKER_1_IP):/tmp/nix-config/k8s-worker-1/"
	@ssh $(REMOTE_HOST) "rsync -avz \
		-e 'ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY)' \
		$(REMOTE_PROJECT_DIR)/iac/provision/nix/k8s-common/ \
		vagrant@$(K8S_WORKER_1_IP):/tmp/nix-config/k8s-common/"
	@ssh $(REMOTE_HOST) "rsync -avz \
		-e 'ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY)' \
		$(REMOTE_PROJECT_DIR)/iac/provision/nix/common/ \
		vagrant@$(K8S_WORKER_1_IP):/tmp/nix-config/common/"
	@echo "$(GREEN)Config synced to k8s-worker-1:/tmp/nix-config/$(NC)"

rebuild-k8s-worker-1: sync-k8s-worker-1 ## Rebuild k8s-worker-1 NixOS config (test mode)
	@echo "$(BLUE)Rebuilding k8s-worker-1 NixOS configuration (test mode)...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-worker-1 -c \
		'sudo nixos-rebuild test -I nixos-config=/tmp/nix-config/k8s-worker-1/configuration.nix'"
	@echo "$(GREEN)Configuration applied (test mode)$(NC)"

rebuild-k8s-worker-1-switch: sync-k8s-worker-1 ## Rebuild and switch k8s-worker-1 NixOS config permanently
	@echo "$(BLUE)Rebuilding k8s-worker-1 NixOS configuration (switch mode)...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-worker-1 -c \
		'sudo nixos-rebuild switch -I nixos-config=/tmp/nix-config/k8s-worker-1/configuration.nix'"
	@echo "$(GREEN)Configuration applied permanently$(NC)"

# Worker 2
sync-k8s-worker-2: ## Sync NixOS configuration to k8s-worker-2 VM
	@echo "$(BLUE)Syncing NixOS config to k8s-worker-2 ($(K8S_WORKER_2_IP))...$(NC)"
	@ssh $(REMOTE_HOST) "ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY) vagrant@$(K8S_WORKER_2_IP) 'mkdir -p /tmp/nix-config'"
	@ssh $(REMOTE_HOST) "rsync -avz \
		-e 'ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY)' \
		$(REMOTE_PROJECT_DIR)/iac/provision/nix/k8s-worker/ \
		vagrant@$(K8S_WORKER_2_IP):/tmp/nix-config/k8s-worker/"
	@ssh $(REMOTE_HOST) "rsync -avz \
		-e 'ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY)' \
		$(REMOTE_PROJECT_DIR)/iac/provision/nix/k8s-worker-2/ \
		vagrant@$(K8S_WORKER_2_IP):/tmp/nix-config/k8s-worker-2/"
	@ssh $(REMOTE_HOST) "rsync -avz \
		-e 'ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY)' \
		$(REMOTE_PROJECT_DIR)/iac/provision/nix/k8s-common/ \
		vagrant@$(K8S_WORKER_2_IP):/tmp/nix-config/k8s-common/"
	@ssh $(REMOTE_HOST) "rsync -avz \
		-e 'ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY)' \
		$(REMOTE_PROJECT_DIR)/iac/provision/nix/common/ \
		vagrant@$(K8S_WORKER_2_IP):/tmp/nix-config/common/"
	@echo "$(GREEN)Config synced to k8s-worker-2:/tmp/nix-config/$(NC)"

rebuild-k8s-worker-2: sync-k8s-worker-2 ## Rebuild k8s-worker-2 NixOS config (test mode)
	@echo "$(BLUE)Rebuilding k8s-worker-2 NixOS configuration (test mode)...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-worker-2 -c \
		'sudo nixos-rebuild test -I nixos-config=/tmp/nix-config/k8s-worker-2/configuration.nix'"
	@echo "$(GREEN)Configuration applied (test mode)$(NC)"

rebuild-k8s-worker-2-switch: sync-k8s-worker-2 ## Rebuild and switch k8s-worker-2 NixOS config permanently
	@echo "$(BLUE)Rebuilding k8s-worker-2 NixOS configuration (switch mode)...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-worker-2 -c \
		'sudo nixos-rebuild switch -I nixos-config=/tmp/nix-config/k8s-worker-2/configuration.nix'"
	@echo "$(GREEN)Configuration applied permanently$(NC)"

# Worker 3
sync-k8s-worker-3: ## Sync NixOS configuration to k8s-worker-3 VM
	@echo "$(BLUE)Syncing NixOS config to k8s-worker-3 ($(K8S_WORKER_3_IP))...$(NC)"
	@ssh $(REMOTE_HOST) "ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY) vagrant@$(K8S_WORKER_3_IP) 'mkdir -p /tmp/nix-config'"
	@ssh $(REMOTE_HOST) "rsync -avz \
		-e 'ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY)' \
		$(REMOTE_PROJECT_DIR)/iac/provision/nix/k8s-worker/ \
		vagrant@$(K8S_WORKER_3_IP):/tmp/nix-config/k8s-worker/"
	@ssh $(REMOTE_HOST) "rsync -avz \
		-e 'ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY)' \
		$(REMOTE_PROJECT_DIR)/iac/provision/nix/k8s-worker-3/ \
		vagrant@$(K8S_WORKER_3_IP):/tmp/nix-config/k8s-worker-3/"
	@ssh $(REMOTE_HOST) "rsync -avz \
		-e 'ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY)' \
		$(REMOTE_PROJECT_DIR)/iac/provision/nix/k8s-common/ \
		vagrant@$(K8S_WORKER_3_IP):/tmp/nix-config/k8s-common/"
	@ssh $(REMOTE_HOST) "rsync -avz \
		-e 'ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY)' \
		$(REMOTE_PROJECT_DIR)/iac/provision/nix/common/ \
		vagrant@$(K8S_WORKER_3_IP):/tmp/nix-config/common/"
	@echo "$(GREEN)Config synced to k8s-worker-3:/tmp/nix-config/$(NC)"

rebuild-k8s-worker-3: sync-k8s-worker-3 ## Rebuild k8s-worker-3 NixOS config (test mode)
	@echo "$(BLUE)Rebuilding k8s-worker-3 NixOS configuration (test mode)...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-worker-3 -c \
		'sudo nixos-rebuild test -I nixos-config=/tmp/nix-config/k8s-worker-3/configuration.nix'"
	@echo "$(GREEN)Configuration applied (test mode)$(NC)"

rebuild-k8s-worker-3-switch: sync-k8s-worker-3 ## Rebuild and switch k8s-worker-3 NixOS config permanently
	@echo "$(BLUE)Rebuilding k8s-worker-3 NixOS configuration (switch mode)...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-worker-3 -c \
		'sudo nixos-rebuild switch -I nixos-config=/tmp/nix-config/k8s-worker-3/configuration.nix'"
	@echo "$(GREEN)Configuration applied permanently$(NC)"

# Cluster operations
k8s-get-token: ## Get RKE2 join token from master
	@echo "$(BLUE)Getting RKE2 join token from k8s-master...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-master -c \
		'sudo cat /var/lib/rancher/rke2/server/node-token'"

k8s-distribute-token: ## Copy join token from master to all workers
	@echo "$(BLUE)Distributing RKE2 join token to workers...$(NC)"
	@TOKEN=$$(ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-master -c 'sudo cat /var/lib/rancher/rke2/server/node-token' 2>/dev/null | tr -d '\r'"); \
	if [ -n "$$TOKEN" ]; then \
		for i in 1 2 3; do \
			echo "Copying token to k8s-worker-$$i..."; \
			ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-worker-$$i -c 'sudo mkdir -p /var/lib/rancher/rke2 && echo \"$$TOKEN\" | sudo tee /var/lib/rancher/rke2/shared-token > /dev/null'"; \
		done; \
		echo "$(GREEN)Token distributed to all workers$(NC)"; \
	else \
		echo "$(RED)Failed to get token from master$(NC)"; \
		exit 1; \
	fi

k8s-kubeconfig: ## Fetch kubeconfig from k8s-master to local machine
	@echo "$(BLUE)Fetching kubeconfig from k8s-master...$(NC)"
	@mkdir -p $(HOME)/.kube
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-master -c 'sudo cat /etc/rancher/rke2/rke2.yaml'" \
		| sed 's/127.0.0.1/k8s-master.support.example.com/g' > $(HOME)/.kube/config-kss
	@chmod 600 $(HOME)/.kube/config-kss
	@echo "$(GREEN)Kubeconfig saved to $(HOME)/.kube/config-kss$(NC)"
	@echo "Usage: export KUBECONFIG=$(HOME)/.kube/config-kss"

k8s-cluster-status: ## Check Kubernetes cluster status
	@echo "$(BLUE)Kubernetes Cluster Status:$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-master -c \
		'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes -o wide'" || true
	@echo ""
	@echo "$(BLUE)System Pods:$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-master -c \
		'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get pods -A'" || true

k8s-master-status: ## Check k8s-master service status
	@echo "$(BLUE)k8s-master Service Status:$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-master -c \
		'systemctl status rke2-server rke2-server-install --no-pager'" || true

k8s-master-logs: ## Show k8s-master RKE2 logs
	@echo "$(BLUE)k8s-master RKE2 Logs:$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-master -c \
		'journalctl -u rke2-server -n 100 --no-pager'"

k8s-worker-logs: ## Show k8s-worker-1 RKE2 agent logs
	@echo "$(BLUE)k8s-worker-1 RKE2 Agent Logs:$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-worker-1 -c \
		'journalctl -u rke2-agent -n 100 --no-pager'"

# ============================================================================
# Cilium Debugging
# ============================================================================

cilium-status: ## Check Cilium status on all nodes
	@echo "$(BLUE)Cilium Pod Status:$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-master -c 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get pods -n kube-system -l k8s-app=cilium -o wide'" || true
	@echo ""
	@echo "$(BLUE)Cilium Agent Status:$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-master -c 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml exec -n kube-system ds/cilium -- cilium status --brief'" || true

cilium-health: ## Check Cilium cluster connectivity health
	@echo "$(BLUE)Cilium Cluster Health:$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-master -c 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml exec -n kube-system ds/cilium -- cilium-health status'" || true

cilium-endpoints: ## List Cilium endpoints on all nodes
	@echo "$(BLUE)Cilium Endpoints:$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-master -c 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml exec -n kube-system ds/cilium -c cilium-agent -- cilium endpoint list'" || true

cilium-services: ## List Cilium service map
	@echo "$(BLUE)Cilium Services:$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-master -c 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml exec -n kube-system ds/cilium -- cilium service list'" || true
	@echo ""
	@echo "$(BLUE)Cilium BPF LB Map:$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-master -c 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml exec -n kube-system ds/cilium -- cilium bpf lb list'" || true

cilium-config: ## Show Cilium configuration
	@echo "$(BLUE)Cilium Configuration:$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-master -c 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml exec -n kube-system ds/cilium -- cilium config -a'" || true

cilium-bpf: ## Show BPF program attachments
	@echo "$(BLUE)BPF Network Attachments:$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-master -c 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml exec -n kube-system ds/cilium -- bpftool net list'" || true

cilium-logs: ## Show Cilium agent logs (last 100 lines)
	@echo "$(BLUE)Cilium Agent Logs:$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-master -c 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml logs -n kube-system ds/cilium --tail=100'" || true

cilium-restart: ## Restart all Cilium pods
	@echo "$(BLUE)Restarting Cilium pods...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-master -c 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml delete pod -n kube-system -l k8s-app=cilium'"
	@echo "$(GREEN)Cilium pods restarting$(NC)"

# Network debugging
net-debug-master: ## Debug network on k8s-master
	@echo "$(BLUE)Network Debug - k8s-master:$(NC)"
	@echo "--- Interfaces ---"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-master -c 'ip -br addr'" || true
	@echo "--- Routes ---"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-master -c 'ip route'" || true

net-debug-worker1: ## Debug network on k8s-worker-1
	@echo "$(BLUE)Network Debug - k8s-worker-1:$(NC)"
	@echo "--- Interfaces ---"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-worker-1 -c 'ip -br addr'" || true
	@echo "--- Routes ---"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-worker-1 -c 'ip route'" || true

net-test-clusterip: ## Test ClusterIP connectivity from each node
	@echo "$(BLUE)Testing ClusterIP from each node:$(NC)"
	@echo "--- Master ---"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-master -c 'curl -k -s -o /dev/null -w \"%{http_code}\" --connect-timeout 3 https://10.43.0.1:443/version'" || echo "FAILED"
	@echo ""
	@echo "--- Worker-1 ---"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-worker-1 -c 'curl -k -s -o /dev/null -w \"%{http_code}\" --connect-timeout 3 https://10.43.0.1:443/version'" || echo "FAILED"
	@echo ""
	@echo "--- Worker-2 ---"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-worker-2 -c 'curl -k -s -o /dev/null -w \"%{http_code}\" --connect-timeout 3 https://10.43.0.1:443/version'" || echo "FAILED"
	@echo ""
	@echo "--- Worker-3 ---"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-worker-3 -c 'curl -k -s -o /dev/null -w \"%{http_code}\" --connect-timeout 3 https://10.43.0.1:443/version'" || echo "FAILED"

# Quick diagnostics
k8s-diag: ## Quick cluster diagnostics
	@echo "$(BLUE)=== Nodes ===$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-master -c 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes -o wide'" || true
	@echo ""
	@echo "$(BLUE)=== Problem Pods ===$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-master -c 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get pods -A'" | grep -vE "Running|Completed" || echo "All pods healthy"
	@echo ""
	@echo "$(BLUE)=== Cilium Status ===$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-master -c 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml exec -n kube-system ds/cilium -- cilium status --brief'" || true
	@echo ""
	@echo "$(BLUE)=== Kubernetes Endpoints ===$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-master -c 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get endpoints -A'" || true

# Rebuild all nodes
k8s-rebuild-all: ## Sync and rebuild all k8s nodes
	@echo "$(BLUE)Rebuilding all Kubernetes nodes...$(NC)"
	@$(MAKE) sync-k8s-master
	@$(MAKE) sync-k8s-worker-1
	@$(MAKE) sync-k8s-worker-2
	@$(MAKE) sync-k8s-worker-3
	@$(MAKE) rebuild-k8s-master-switch
	@echo "$(BLUE)Ensuring rke2-server is running...$(NC)"
	@ssh $(REMOTE_HOST) "ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY) vagrant@$(K8S_MASTER_IP) 'sudo systemctl start rke2-server 2>/dev/null || true'"
	@echo "$(BLUE)Waiting for RKE2 server to generate join token...$(NC)"
	@for i in $$(seq 1 60); do \
		TOKEN=$$(ssh $(REMOTE_HOST) "ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY) vagrant@$(K8S_MASTER_IP) 'sudo cat /var/lib/rancher/rke2/server/node-token 2>/dev/null'" 2>/dev/null | tr -d '\r'); \
		if [ -n "$$TOKEN" ]; then \
			echo "$(GREEN)Token available$(NC)"; \
			break; \
		fi; \
		echo "  Attempt $$i/60 - waiting for token..."; \
		sleep 5; \
	done
	@$(MAKE) k8s-distribute-token
	@$(MAKE) rebuild-k8s-worker-1-switch
	@$(MAKE) rebuild-k8s-worker-2-switch
	@$(MAKE) rebuild-k8s-worker-3-switch
	@echo "$(GREEN)All nodes rebuilt$(NC)"

# SSH shortcuts
vagrant-ssh-k8s-master: ## SSH into k8s-master VM (via iter)
	@ssh -t $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-master"

vagrant-ssh-k8s-worker-1: ## SSH into k8s-worker-1 VM (via iter)
	@ssh -t $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-worker-1"

vagrant-ssh-k8s-worker-2: ## SSH into k8s-worker-2 VM (via iter)
	@ssh -t $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-worker-2"

vagrant-ssh-k8s-worker-3: ## SSH into k8s-worker-3 VM (via iter)
	@ssh -t $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-worker-3"

# ============================================================================
# Network Configuration Generation
# ============================================================================

generate-network-config: ## Generate Cilium CRDs and UniFi FRR config from config.yaml
	@echo "$(BLUE)Generating network configuration files...$(NC)"
	@./iac/network/generate.sh
	@echo "$(GREEN)Network configuration generated$(NC)"

# ============================================================================
# Vault & Secrets Management
# ============================================================================

bootstrap-vault-k8s: ## Bootstrap Vault for Kubernetes external-secrets integration
	@echo "$(BLUE)Bootstrapping Vault for Kubernetes...$(NC)"
	@echo "This script will:"
	@echo "  1. Enable KV v2 secrets engine"
	@echo "  2. Load secrets from sops-encrypted file"
	@echo "  3. Configure Kubernetes authentication"
	@echo "  4. Create policies for external-secrets"
	@echo ""
	@echo "Prerequisites:"
	@echo "  - VAULT_ADDR must be set (e.g., https://vault.support.example.com)"
	@echo "  - VAULT_TOKEN must be set (root token from make vault-show-token)"
	@echo "  - KUBECONFIG must point to the k8s cluster"
	@echo ""
	@if [ -z "$${VAULT_ADDR:-}" ]; then \
		echo "$(RED)ERROR: VAULT_ADDR not set$(NC)"; \
		echo "Run: export VAULT_ADDR=https://vault.support.example.com"; \
		exit 1; \
	fi
	@if [ -z "$${VAULT_TOKEN:-}" ]; then \
		echo "$(RED)ERROR: VAULT_TOKEN not set$(NC)"; \
		echo "Run: export VAULT_TOKEN=\$$(make vault-token)"; \
		exit 1; \
	fi
	@./iac/scripts/bootstrap-vault-k8s.sh
	@echo "$(GREEN)Vault bootstrap complete$(NC)"

apply-vault-auth: ## Apply vault-auth kustomize resources to cluster
	@echo "$(BLUE)Applying vault-auth resources...$(NC)"
	@if [ -z "$${KUBECONFIG:-}" ]; then \
		echo "$(RED)ERROR: KUBECONFIG not set$(NC)"; \
		echo "Run: export KUBECONFIG=~/.kube/config-kss"; \
		exit 1; \
	fi
	@kubectl apply -k $(KUSTOMIZE_DIR)/base/vault-auth/
	@echo "$(GREEN)vault-auth resources applied$(NC)"
	@echo "Waiting for token to be populated..."
	@sleep 2
	@kubectl get secret vault-auth-token -n vault-auth -o jsonpath='{.data.token}' | base64 -d | head -c 50
	@echo "..."
	@echo ""
	@echo "$(GREEN)Token is ready. Run 'make configure-vault-k8s-auth' to configure Vault$(NC)"

configure-vault-k8s-auth: ## Configure Vault Kubernetes auth with token reviewer JWT
	@echo "$(BLUE)Configuring Vault Kubernetes auth...$(NC)"
	@if [ -z "$${VAULT_ADDR:-}" ]; then \
		echo "$(RED)ERROR: VAULT_ADDR not set$(NC)"; \
		echo "Run: export VAULT_ADDR=https://vault.support.example.com"; \
		exit 1; \
	fi
	@if [ -z "$${VAULT_TOKEN:-}" ]; then \
		echo "$(RED)ERROR: VAULT_TOKEN not set$(NC)"; \
		echo "Run: export VAULT_TOKEN=\$$(make vault-token)"; \
		exit 1; \
	fi
	@if [ -z "$${KUBECONFIG:-}" ]; then \
		echo "$(RED)ERROR: KUBECONFIG not set$(NC)"; \
		echo "Run: export KUBECONFIG=~/.kube/config-kss"; \
		exit 1; \
	fi
	@./iac/scripts/configure-vault-k8s-auth.sh
	@echo "$(GREEN)Vault Kubernetes auth configured$(NC)"

# ============================================================================
# Deployment (Kustomize + Helmfile)
# ============================================================================
#
# Full deployment sequence:
#   1. vault-auth SA        → k8s can authenticate to Vault
#   2. Vault k8s auth config → Vault trusts this cluster's CA + JWT
#   3. helmfile apply        → installs operators (cert-manager, external-secrets, nginx-ingress, etc.)
#   4. ExternalSecrets       → ClusterSecretStore + ExternalSecrets sync Cloudflare token from Vault
#   5. cert-manager resources → ClusterIssuers + wildcard certificate
#
# Prerequisites:
#   - KUBECONFIG pointing to the k8s cluster
#   - Vault backup keys at iac/.vault-keys-backup.json (for root token)
#   - Vault already bootstrapped (secrets loaded, k8s auth enabled, role created)
#     If not, run: make bootstrap-vault-k8s

VAULT_URL ?= https://vault.support.example.com

k8s-deploy-vault-auth: ## Apply vault-auth SA and update Vault k8s auth config
	@if [ -z "$${KUBECONFIG:-}" ]; then \
		echo "$(RED)ERROR: KUBECONFIG not set$(NC)"; \
		echo "Run: export KUBECONFIG=~/.kube/config-kss"; \
		exit 1; \
	fi
	@if [ ! -f "$(VAULT_KEYS_BACKUP)" ]; then \
		echo "$(RED)ERROR: Vault keys backup not found at $(VAULT_KEYS_BACKUP)$(NC)"; \
		echo "Run: make vault-backup-keys"; \
		exit 1; \
	fi
	@echo "$(BLUE)Applying vault-auth service account...$(NC)"
	@kubectl apply -k $(KUSTOMIZE_DIR)/base/vault-auth/
	@echo "$(BLUE)Waiting for vault-auth token...$(NC)"
	@for i in $$(seq 1 30); do \
		TOKEN=$$(kubectl get secret vault-auth-token -n vault-auth -o jsonpath='{.data.token}' 2>/dev/null | base64 -d); \
		if [ -n "$$TOKEN" ]; then break; fi; \
		sleep 1; \
	done; \
	if [ -z "$$TOKEN" ]; then echo "$(RED)ERROR: Timed out waiting for vault-auth token$(NC)"; exit 1; fi
	@echo "$(BLUE)Updating Vault Kubernetes auth config...$(NC)"
	@VAULT_TOKEN=$$(jq -r '.root_token' $(VAULT_KEYS_BACKUP)); \
	SA_JWT=$$(kubectl get secret vault-auth-token -n vault-auth -o jsonpath='{.data.token}' | base64 -d); \
	K8S_CA=$$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d); \
	K8S_HOST=$$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'); \
	RESULT=$$(curl -sk -w "\n%{http_code}" -X POST \
		-H "X-Vault-Token: $$VAULT_TOKEN" \
		-d "$$(jq -n --arg host "$$K8S_HOST" --arg jwt "$$SA_JWT" --arg ca "$$K8S_CA" \
			'{kubernetes_host: $$host, token_reviewer_jwt: $$jwt, kubernetes_ca_cert: $$ca, disable_iss_validation: true}')" \
		$(VAULT_URL)/v1/auth/kubernetes/config); \
	HTTP_CODE=$$(echo "$$RESULT" | tail -1); \
	if [ "$$HTTP_CODE" != "204" ] && [ "$$HTTP_CODE" != "200" ]; then \
		echo "$(RED)ERROR: Vault returned HTTP $$HTTP_CODE$(NC)"; \
		echo "$$RESULT" | head -n -1; \
		exit 1; \
	fi
	@echo "$(GREEN)Vault k8s auth configured for this cluster$(NC)"

k8s-deploy-secrets: ## Apply ClusterSecretStore + ExternalSecrets + cert-manager resources
	@if [ -z "$${KUBECONFIG:-}" ]; then \
		echo "$(RED)ERROR: KUBECONFIG not set$(NC)"; \
		echo "Run: export KUBECONFIG=~/.kube/config-kss"; \
		exit 1; \
	fi
	@echo "$(BLUE)Applying ClusterSecretStore and ExternalSecrets...$(NC)"
	@kubectl apply -k $(KUSTOMIZE_DIR)/base/external-secrets/
	@echo "$(BLUE)Waiting for secrets to sync...$(NC)"
	@for i in $$(seq 1 30); do \
		STATUS=$$(kubectl get externalsecret cloudflare-api-token -n cert-manager -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null); \
		if [ "$$STATUS" = "SecretSynced" ]; then break; fi; \
		sleep 2; \
	done; \
	if [ "$$STATUS" != "SecretSynced" ]; then \
		echo "$(RED)WARNING: ExternalSecret not yet synced (status: $$STATUS). Check ClusterSecretStore.$(NC)"; \
	else \
		echo "$(GREEN)Cloudflare secrets synced from Vault$(NC)"; \
	fi
	@echo "$(BLUE)Applying cert-manager ClusterIssuers and certificates...$(NC)"
	@kubectl apply -k $(KUSTOMIZE_DIR)/base/cert-manager/
	@echo "$(GREEN)Secrets and cert-manager resources applied$(NC)"

k8s-deploy-base-resources: k8s-deploy-vault-auth k8s-deploy-secrets ## Apply all kustomize base resources (vault-auth + secrets + cert-manager)

k8s-deploy-default: k8s-deploy-vault-auth ## Deploy default profile (MetalLB L2 + nginx-ingress, no Cilium)
	@echo "$(BLUE)Deploying MetalLB...$(NC)"
	@cd $(HELMFILE_DIR) && helmfile -e default -l name=metallb apply
	@echo "$(BLUE)Applying MetalLB L2 address pool...$(NC)"
	@kubectl apply -k $(KUSTOMIZE_DIR)/base/metallb/
	@echo "$(BLUE)Deploying remaining helmfile releases...$(NC)"
	@cd $(HELMFILE_DIR) && helmfile -e default apply
	@$(MAKE) k8s-deploy-secrets
	@echo "$(GREEN)Default deployment complete$(NC)"
	@echo "nginx-ingress LoadBalancer IP allocated from 10.69.50.192/27 via MetalLB L2"

k8s-deploy-bgp-simple: k8s-deploy-vault-auth ## Deploy Cilium BGP + nginx-ingress profile
	@echo "$(BLUE)Deploying helmfile bgp-simple environment...$(NC)"
	@cd $(HELMFILE_DIR) && helmfile -e bgp-simple apply
	@$(MAKE) k8s-deploy-secrets
	@echo "$(BLUE)Applying kustomize cilium-bgp overlay...$(NC)"
	@kubectl apply -k $(KUSTOMIZE_DIR)/overlays/cilium-bgp
	@echo "$(GREEN)BGP simple deployment complete$(NC)"

k8s-deploy-gateway-bgp: k8s-deploy-vault-auth ## Deploy Cilium BGP + Gateway API profile
	@echo "$(BLUE)Deploying helmfile gateway-bgp environment...$(NC)"
	@cd $(HELMFILE_DIR) && helmfile -e gateway-bgp apply
	@$(MAKE) k8s-deploy-secrets
	@echo "$(BLUE)Applying kustomize cilium-gateway overlay...$(NC)"
	@kubectl apply -k $(KUSTOMIZE_DIR)/overlays/cilium-gateway
	@echo "$(GREEN)Gateway BGP deployment complete$(NC)"

# ============================================================================
# Validation & Testing
# ============================================================================

validate: validate-helm validate-kustomize ## Run all validations

validate-helm: ## Validate Helmfile
	@echo "$(BLUE)Validating Helmfile...$(NC)"
	@if command -v helmfile &> /dev/null; then \
		cd $(HELMFILE_DIR) && helmfile lint; \
		echo "$(GREEN)Helmfile validation passed!$(NC)"; \
	else \
		echo "$(RED)helmfile not found$(NC)"; \
	fi

validate-kustomize: ## Validate Kustomize manifests
	@echo "$(BLUE)Validating Kustomize manifests...$(NC)"
	@if command -v kustomize &> /dev/null; then \
		echo "  Validating base..."; \
		kustomize build $(KUSTOMIZE_DIR)/base > /dev/null && \
		echo "  $(GREEN)base: OK$(NC)" || \
		echo "  $(RED)base: FAILED$(NC)"; \
		echo "  Validating cilium-bgp overlay..."; \
		kustomize build $(KUSTOMIZE_DIR)/overlays/cilium-bgp > /dev/null && \
		echo "  $(GREEN)cilium-bgp: OK$(NC)" || \
		echo "  $(RED)cilium-bgp: FAILED$(NC)"; \
		echo "  Validating cilium-gateway overlay..."; \
		kustomize build $(KUSTOMIZE_DIR)/overlays/cilium-gateway > /dev/null && \
		echo "  $(GREEN)cilium-gateway: OK$(NC)" || \
		echo "  $(RED)cilium-gateway: FAILED$(NC)"; \
	else \
		echo "$(RED)kustomize not found$(NC)"; \
	fi

lint: ## Run all linters
	@echo "$(BLUE)Linting configurations...$(NC)"
	@echo "Checking documentation files..."
	@find $(DOCS_DIR) -name "*.md" -exec echo "  {}" \;
	@echo "$(GREEN)Linting complete!$(NC)"

test: ## Run smoke tests (requires running cluster)
	@echo "$(BLUE)Running smoke tests...$(NC)"
	@if [ -f "$(HOME)/.kube/config-kss" ]; then \
		KUBECONFIG=$(HOME)/.kube/config-kss kubectl cluster-info; \
	else \
		echo "$(RED)No kubeconfig found. Run 'make k8s-kubeconfig' first.$(NC)"; \
	fi

# ============================================================================
# Build Tools
# ============================================================================

build-nix-box: ## Build custom NixOS Vagrant box
	@echo "$(BLUE)Building custom NixOS Vagrant box...$(NC)"
	@cd iac && bash build-nix-box.sh
	@echo "$(GREEN)Box built successfully!$(NC)"

# ============================================================================
# Utility
# ============================================================================

print-config: ## Print configuration variables
	@echo "$(BLUE)Configuration:$(NC)"
	@echo "Local Vagrant Directory: $(VAGRANT_DIR)"
	@echo "Remote Host: $(REMOTE_HOST)"
	@echo "Remote Vagrant Directory: $(REMOTE_VAGRANT_DIR)"
	@echo "Helmfile Directory: $(HELMFILE_DIR)"
	@echo "Docs Directory: $(DOCS_DIR)"
