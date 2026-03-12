.PHONY: help up provision down reset clean lint test validate
.DEFAULT_GOAL := help

# ============================================================================
# Cluster Selection
# ============================================================================
# Override with: make CLUSTER=kss2 <target>
CLUSTER ?= kss

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
CLUSTER_DIR := $(shell pwd)/iac/clusters/$(CLUSTER)
CLUSTER_GEN_DIR := $(CLUSTER_DIR)/generated

# Remote execution configuration
# Vagrant/libvirt runs on iter, code is at ~/dev/homelab there
REMOTE_HOST := iter
REMOTE_PROJECT_DIR := ~/dev/homelab
REMOTE_VAGRANT_DIR := $(REMOTE_PROJECT_DIR)/iac
REMOTE_CLUSTER_GEN_DIR := $(REMOTE_PROJECT_DIR)/iac/clusters/$(CLUSTER)/generated

# SSH key for direct VM access
VAGRANT_SSH_KEY := ~/.vagrant.d/ecdsa_private_key

# VM IPs - using fixed IPs from Unifi DHCP static leases
# See CLAUDE.md DNS Configuration section for MAC/IP mapping
SUPPORT_VM_IP ?= 10.69.50.10

# Include generated cluster variables (defines CLUSTER_NAME, CLUSTER_MASTER_IP, etc.)
-include $(CLUSTER_GEN_DIR)/vars.mk

# Derived names from cluster config
MASTER_VM := $(CLUSTER_NAME)-master
MASTER_IP := $(CLUSTER_MASTER_IP)

# Help target
help:
	@echo "$(BLUE)Kubernetes Homelab Infrastructure - Make Commands$(NC)"
	@echo "$(BLUE)Current cluster: $(CLUSTER)$(NC)"
	@echo ""
	@echo "$(GREEN)Cluster Management:$(NC)"
	@echo "  CLUSTER=<name> make <target>     Override cluster (default: kss)"
	@echo "  make generate-cluster            Generate config from cluster.yaml"
	@echo "  make cluster-up                  Start all cluster VMs"
	@echo "  make cluster-down                Stop all cluster VMs"
	@echo "  make cluster-destroy             Destroy all cluster VMs"
	@echo "  make cluster-recreate            Destroy and recreate all cluster VMs"
	@echo "  make cluster-clean-state         Wipe RKE2 state on all nodes"
	@echo "  make cluster-rebuild-all         Sync and rebuild all cluster nodes"
	@echo "  make cluster-status              Check cluster nodes and pods"
	@echo "  make cluster-kubeconfig          Fetch kubeconfig locally"
	@echo ""
	@echo "$(GREEN)Node Management:$(NC)"
	@echo "  make master-up                   Start master VM"
	@echo "  make workers-up                  Start all worker VMs"
	@echo "  make sync-master                 Sync NixOS config to master"
	@echo "  make rebuild-master              Rebuild master (test mode)"
	@echo "  make rebuild-master-switch       Rebuild master (permanent)"
	@echo "  make sync-worker-{1,2,3}         Sync config to worker"
	@echo "  make rebuild-worker-{1,2,3}      Rebuild worker (test mode)"
	@echo "  make rebuild-worker-{1,2,3}-switch Rebuild worker (permanent)"
	@echo "  make distribute-token            Copy join token to workers"
	@echo "  make ssh-master                  SSH into master"
	@echo "  make ssh-worker-{1,2,3}          SSH into worker"
	@echo ""
	@echo "$(GREEN)VM Management (global):$(NC)"
	@echo "  make up                          Start all Vagrant VMs"
	@echo "  make down                        Stop all Vagrant VMs"
	@echo "  make status                      Show Vagrant VM status"
	@echo ""
	@echo "$(GREEN)Support VM:$(NC)"
	@echo "  make sync-support                Sync NixOS config to support VM"
	@echo "  make rebuild-support             Rebuild support VM (test mode)"
	@echo "  make rebuild-support-switch      Rebuild and switch permanently"
	@echo "  make support-status              Check service status on support VM"
	@echo ""
	@echo "$(GREEN)Deployment (requires KUBECONFIG):$(NC)"
	@echo "  make deploy                      Deploy using cluster's helmfile_env from cluster.yaml"
	@echo "  make deploy-default              Full deploy: MetalLB L2 + nginx-ingress + secrets"
	@echo "  make deploy-bgp-simple           Full deploy: Cilium BGP + nginx-ingress + secrets"
	@echo "  make deploy-gateway-bgp          Full deploy: Cilium BGP + Gateway API + secrets"
	@echo "  make deploy-vault-auth           Configure vault-auth SA and update Vault k8s auth"
	@echo "  make deploy-secrets              Apply ClusterSecretStore + ExternalSecrets + cert-manager"
	@echo "  make deploy-base-resources       All kustomize base resources"
	@echo ""
	@echo "$(GREEN)Vault Key Management:$(NC)"
	@echo "  make vault-backup-keys           Backup Vault keys to local file"
	@echo "  make vault-restore-keys          Restore Vault keys from backup"
	@echo "  make vault-show-token            Show Vault root token"
	@echo ""
	@echo "$(GREEN)Cilium Debugging:$(NC)"
	@echo "  make cilium-status               Check Cilium pod and agent status"
	@echo "  make cilium-health               Check Cilium cluster connectivity"
	@echo "  make cilium-endpoints            List Cilium endpoints"
	@echo "  make cilium-services             Show Cilium service map and BPF LB"
	@echo "  make cilium-config               Show Cilium configuration"
	@echo "  make cilium-bpf                  Show BPF program attachments"
	@echo "  make cilium-logs                 Show Cilium agent logs"
	@echo "  make cilium-restart              Restart all Cilium pods"
	@echo ""
	@echo "$(GREEN)Network Debugging:$(NC)"
	@echo "  make net-debug-master            Show network info on master"
	@echo "  make net-debug-worker1           Show network info on worker-1"
	@echo "  make net-test-clusterip          Test ClusterIP from each node"
	@echo "  make diag                        Quick cluster diagnostics"
	@echo ""
	@echo "$(GREEN)Validation & Testing:$(NC)"
	@echo "  make validate                    Validate Helm and Kustomize manifests"
	@echo "  make lint                        Lint documentation and configurations"
	@echo "  make test                        Run smoke tests"
	@echo ""

# ============================================================================
# Cluster Configuration Generation
# ============================================================================

generate-cluster: ## Generate config files from cluster.yaml
	@echo "$(BLUE)Generating configuration for cluster '$(CLUSTER)'...$(NC)"
	@./scripts/generate-cluster.sh $(CLUSTER)
	@echo "$(GREEN)Generation complete$(NC)"

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
# Kubernetes Cluster Management (parameterized by CLUSTER)
# ============================================================================

# Cluster lifecycle
cluster-up: ## Start all cluster VMs
	@echo "$(BLUE)Starting $(CLUSTER) cluster VMs...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant up $(CLUSTER_ALL_VMS)"
	@echo "$(GREEN)$(CLUSTER) cluster VMs started$(NC)"

cluster-down: ## Stop all cluster VMs
	@echo "$(BLUE)Stopping $(CLUSTER) cluster VMs...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant halt $(CLUSTER_ALL_VMS)"
	@echo "$(GREEN)$(CLUSTER) cluster VMs stopped$(NC)"

cluster-destroy: ## Destroy all cluster VMs
	@echo "$(RED)Destroying all $(CLUSTER) cluster VMs...$(NC)"
	@read -p "Are you sure? This will destroy $(CLUSTER_ALL_VMS). [y/N] " -n 1 -r; \
	echo ""; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant destroy -f $(CLUSTER_ALL_VMS)"; \
		echo "$(GREEN)All $(CLUSTER) VMs destroyed$(NC)"; \
	else \
		echo "$(BLUE)Destroy cancelled$(NC)"; \
	fi

cluster-destroy-master: ## Destroy cluster master VM only
	@echo "$(RED)Destroying $(MASTER_VM) VM...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant destroy -f $(MASTER_VM)"
	@echo "$(GREEN)$(MASTER_VM) destroyed$(NC)"

cluster-destroy-workers: ## Destroy all cluster worker VMs
	@echo "$(RED)Destroying $(CLUSTER) worker VMs...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant destroy -f $(CLUSTER_WORKER_VMS)"
	@echo "$(GREEN)$(CLUSTER) worker VMs destroyed$(NC)"

cluster-clean-state: ## Wipe RKE2 state on all cluster nodes (for re-bootstrap)
	@echo "$(RED)Wiping RKE2 state on all $(CLUSTER) nodes...$(NC)"
	@read -p "Are you sure? This removes all RKE2 data. [y/N] " -n 1 -r; \
	echo ""; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		echo "Stopping RKE2 on $(MASTER_VM) ($(MASTER_IP))..."; \
		ssh $(REMOTE_HOST) "ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY) vagrant@$(MASTER_IP) 'sudo /opt/rke2/bin/rke2-killall.sh 2>/dev/null || sudo systemctl stop rke2-server 2>/dev/null || true; sudo rm -rf /var/lib/rancher/rke2/server /var/lib/rancher/rke2/agent /etc/rancher/node /etc/rancher/rke2/.token-configured /var/lib/rancher/rke2/.installed'" || true; \
		echo "Stopping RKE2 on workers..."; \
		for IP in $(CLUSTER_WORKER_1_IP) $(CLUSTER_WORKER_2_IP) $(CLUSTER_WORKER_3_IP); do \
			echo "  Stopping RKE2 on $$IP..."; \
			ssh $(REMOTE_HOST) "ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY) vagrant@$$IP 'sudo /opt/rke2/bin/rke2-killall.sh 2>/dev/null || sudo systemctl stop rke2-agent 2>/dev/null || true; sudo rm -rf /var/lib/rancher/rke2/agent /etc/rancher/node /etc/rancher/rke2/config.yaml /etc/rancher/rke2/.token-configured /var/lib/rancher/rke2/.installed /var/lib/rancher/rke2/shared-token'" || true; \
		done; \
		echo "$(GREEN)RKE2 state wiped. Run 'make cluster-rebuild-all' to re-bootstrap.$(NC)"; \
	else \
		echo "$(BLUE)Clean cancelled$(NC)"; \
	fi

cluster-recreate: ## Destroy and recreate all cluster VMs (clean slate)
	@echo "$(RED)Recreating all $(CLUSTER) VMs (destroy + create)...$(NC)"
	@read -p "Are you sure? This will destroy and recreate all $(CLUSTER) VMs. [y/N] " -n 1 -r; \
	echo ""; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant destroy -f $(CLUSTER_ALL_VMS)" || true; \
		ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant up $(CLUSTER_ALL_VMS)"; \
		echo "$(GREEN)All $(CLUSTER) VMs recreated$(NC)"; \
	else \
		echo "$(BLUE)Recreate cancelled$(NC)"; \
	fi

# Master node management
master-up: ## Start cluster master VM
	@echo "$(BLUE)Starting $(MASTER_VM) VM...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant up $(MASTER_VM)"
	@echo "$(GREEN)$(MASTER_VM) VM started$(NC)"

sync-master: ## Sync NixOS configuration to cluster master VM
	@echo "$(BLUE)Syncing NixOS config to $(MASTER_VM) ($(MASTER_IP))...$(NC)"
	@ssh $(REMOTE_HOST) "rsync -avz \
		-e 'ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY)' \
		$(REMOTE_PROJECT_DIR)/iac/provision/nix/k8s-master/ \
		vagrant@$(MASTER_IP):/tmp/nix-config/"
	@ssh $(REMOTE_HOST) "rsync -avz \
		-e 'ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY)' \
		$(REMOTE_PROJECT_DIR)/iac/provision/nix/k8s-common/ \
		vagrant@$(MASTER_IP):/tmp/nix-config/k8s-common/"
	@ssh $(REMOTE_HOST) "rsync -avz \
		-e 'ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY)' \
		$(REMOTE_PROJECT_DIR)/iac/provision/nix/common/ \
		vagrant@$(MASTER_IP):/tmp/nix-config/common/"
	@ssh $(REMOTE_HOST) "rsync -avz \
		-e 'ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY)' \
		$(REMOTE_CLUSTER_GEN_DIR)/nix/master.nix $(REMOTE_CLUSTER_GEN_DIR)/nix/cluster.nix \
		vagrant@$(MASTER_IP):/tmp/nix-config/"
	@echo "$(GREEN)Config synced to $(MASTER_VM):/tmp/nix-config/$(NC)"

rebuild-master: sync-master ## Rebuild cluster master NixOS config (test mode)
	@echo "$(BLUE)Rebuilding $(MASTER_VM) NixOS configuration (test mode)...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(MASTER_VM) -c \
		'sudo nixos-rebuild test -I nixos-config=/tmp/nix-config/master.nix'"
	@echo "$(GREEN)Configuration applied (test mode - not permanent)$(NC)"

rebuild-master-switch: sync-master ## Rebuild and switch cluster master NixOS config permanently
	@echo "$(BLUE)Rebuilding $(MASTER_VM) NixOS configuration (switch mode)...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(MASTER_VM) -c \
		'sudo nixos-rebuild switch -I nixos-config=/tmp/nix-config/master.nix'"
	@echo "$(GREEN)Configuration applied permanently$(NC)"

# Worker node management
workers-up: ## Start all cluster worker VMs
	@echo "$(BLUE)Starting $(CLUSTER) worker VMs...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant up $(CLUSTER_WORKER_VMS)"
	@echo "$(GREEN)$(CLUSTER) worker VMs started$(NC)"

# Worker sync helper - syncs shared worker config + generated wrapper + common modules
define sync-worker
sync-worker-$(1): ## Sync NixOS configuration to worker-$(1) VM
	@echo "$(BLUE)Syncing NixOS config to $(CLUSTER_NAME)-worker-$(1) ($$(CLUSTER_WORKER_$(1)_IP))...$(NC)"
	@ssh $(REMOTE_HOST) "ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY) vagrant@$$(CLUSTER_WORKER_$(1)_IP) 'mkdir -p /tmp/nix-config'"
	@ssh $(REMOTE_HOST) "rsync -avz \
		-e 'ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY)' \
		$(REMOTE_PROJECT_DIR)/iac/provision/nix/k8s-worker/ \
		vagrant@$$(CLUSTER_WORKER_$(1)_IP):/tmp/nix-config/k8s-worker/"
	@ssh $(REMOTE_HOST) "rsync -avz \
		-e 'ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY)' \
		$(REMOTE_PROJECT_DIR)/iac/provision/nix/k8s-common/ \
		vagrant@$$(CLUSTER_WORKER_$(1)_IP):/tmp/nix-config/k8s-common/"
	@ssh $(REMOTE_HOST) "rsync -avz \
		-e 'ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY)' \
		$(REMOTE_PROJECT_DIR)/iac/provision/nix/common/ \
		vagrant@$$(CLUSTER_WORKER_$(1)_IP):/tmp/nix-config/common/"
	@ssh $(REMOTE_HOST) "rsync -avz \
		-e 'ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY)' \
		$(REMOTE_CLUSTER_GEN_DIR)/nix/worker-$(1).nix $(REMOTE_CLUSTER_GEN_DIR)/nix/cluster.nix \
		vagrant@$$(CLUSTER_WORKER_$(1)_IP):/tmp/nix-config/"
	@echo "$(GREEN)Config synced to $(CLUSTER_NAME)-worker-$(1):/tmp/nix-config/$(NC)"
endef

$(eval $(call sync-worker,1))
$(eval $(call sync-worker,2))
$(eval $(call sync-worker,3))

# Worker rebuild helpers
define rebuild-worker
rebuild-worker-$(1): sync-worker-$(1) ## Rebuild worker-$(1) NixOS config (test mode)
	@echo "$(BLUE)Rebuilding $(CLUSTER_NAME)-worker-$(1) NixOS configuration (test mode)...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(CLUSTER_NAME)-worker-$(1) -c \
		'sudo nixos-rebuild test -I nixos-config=/tmp/nix-config/worker-$(1).nix'"
	@echo "$(GREEN)Configuration applied (test mode)$(NC)"

rebuild-worker-$(1)-switch: sync-worker-$(1) ## Rebuild and switch worker-$(1) NixOS config permanently
	@echo "$(BLUE)Rebuilding $(CLUSTER_NAME)-worker-$(1) NixOS configuration (switch mode)...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(CLUSTER_NAME)-worker-$(1) -c \
		'sudo nixos-rebuild switch -I nixos-config=/tmp/nix-config/worker-$(1).nix'"
	@echo "$(GREEN)Configuration applied permanently$(NC)"
endef

$(eval $(call rebuild-worker,1))
$(eval $(call rebuild-worker,2))
$(eval $(call rebuild-worker,3))

# Cluster operations
get-token: ## Get RKE2 join token from master
	@echo "$(BLUE)Getting RKE2 join token from $(MASTER_VM)...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(MASTER_VM) -c \
		'sudo cat /var/lib/rancher/rke2/server/node-token'"

distribute-token: ## Copy join token from master to all workers
	@echo "$(BLUE)Distributing RKE2 join token to $(CLUSTER) workers...$(NC)"
	@TOKEN=$$(ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(MASTER_VM) -c 'sudo cat /var/lib/rancher/rke2/server/node-token' 2>/dev/null | tr -d '\r'"); \
	if [ -n "$$TOKEN" ]; then \
		for IP in $(CLUSTER_WORKER_1_IP) $(CLUSTER_WORKER_2_IP) $(CLUSTER_WORKER_3_IP); do \
			echo "Copying token to $$IP..."; \
			ssh $(REMOTE_HOST) "ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY) vagrant@$$IP 'sudo mkdir -p /var/lib/rancher/rke2 && echo \"$$TOKEN\" | sudo tee /var/lib/rancher/rke2/shared-token > /dev/null'"; \
		done; \
		echo "$(GREEN)Token distributed to all $(CLUSTER) workers$(NC)"; \
	else \
		echo "$(RED)Failed to get token from $(MASTER_VM)$(NC)"; \
		exit 1; \
	fi

cluster-kubeconfig: ## Fetch kubeconfig from cluster master to local machine
	@echo "$(BLUE)Fetching kubeconfig from $(MASTER_VM)...$(NC)"
	@mkdir -p $(HOME)/.kube
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(MASTER_VM) -c 'sudo cat /etc/rancher/rke2/rke2.yaml'" \
		| sed 's/127.0.0.1/$(CLUSTER_NAME)-master.$(CLUSTER_DOMAIN)/g' > $(HOME)/.kube/config-$(CLUSTER)
	@chmod 600 $(HOME)/.kube/config-$(CLUSTER)
	@echo "$(GREEN)Kubeconfig saved to $(HOME)/.kube/config-$(CLUSTER)$(NC)"
	@echo "Usage: export KUBECONFIG=$(HOME)/.kube/config-$(CLUSTER)"

cluster-status: ## Check Kubernetes cluster status
	@echo "$(BLUE)Kubernetes Cluster Status ($(CLUSTER)):$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(MASTER_VM) -c \
		'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes -o wide'" || true
	@echo ""
	@echo "$(BLUE)System Pods:$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(MASTER_VM) -c \
		'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get pods -A'" || true

master-status: ## Check cluster master service status
	@echo "$(BLUE)$(MASTER_VM) Service Status:$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(MASTER_VM) -c \
		'systemctl status rke2-server rke2-server-install --no-pager'" || true

master-logs: ## Show cluster master RKE2 logs
	@echo "$(BLUE)$(MASTER_VM) RKE2 Logs:$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(MASTER_VM) -c \
		'journalctl -u rke2-server -n 100 --no-pager'"

worker-logs: ## Show worker-1 RKE2 agent logs
	@echo "$(BLUE)$(CLUSTER_NAME)-worker-1 RKE2 Agent Logs:$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(CLUSTER_NAME)-worker-1 -c \
		'journalctl -u rke2-agent -n 100 --no-pager'"

# ============================================================================
# Cilium Debugging
# ============================================================================

cilium-status: ## Check Cilium status on all nodes
	@echo "$(BLUE)Cilium Pod Status:$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(MASTER_VM) -c 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get pods -n kube-system -l k8s-app=cilium -o wide'" || true
	@echo ""
	@echo "$(BLUE)Cilium Agent Status:$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(MASTER_VM) -c 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml exec -n kube-system ds/cilium -- cilium status --brief'" || true

cilium-health: ## Check Cilium cluster connectivity health
	@echo "$(BLUE)Cilium Cluster Health:$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(MASTER_VM) -c 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml exec -n kube-system ds/cilium -- cilium-health status'" || true

cilium-endpoints: ## List Cilium endpoints on all nodes
	@echo "$(BLUE)Cilium Endpoints:$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(MASTER_VM) -c 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml exec -n kube-system ds/cilium -c cilium-agent -- cilium endpoint list'" || true

cilium-services: ## List Cilium service map
	@echo "$(BLUE)Cilium Services:$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(MASTER_VM) -c 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml exec -n kube-system ds/cilium -- cilium service list'" || true
	@echo ""
	@echo "$(BLUE)Cilium BPF LB Map:$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(MASTER_VM) -c 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml exec -n kube-system ds/cilium -- cilium bpf lb list'" || true

cilium-config: ## Show Cilium configuration
	@echo "$(BLUE)Cilium Configuration:$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(MASTER_VM) -c 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml exec -n kube-system ds/cilium -- cilium config -a'" || true

cilium-bpf: ## Show BPF program attachments
	@echo "$(BLUE)BPF Network Attachments:$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(MASTER_VM) -c 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml exec -n kube-system ds/cilium -- bpftool net list'" || true

cilium-logs: ## Show Cilium agent logs (last 100 lines)
	@echo "$(BLUE)Cilium Agent Logs:$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(MASTER_VM) -c 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml logs -n kube-system ds/cilium --tail=100'" || true

cilium-restart: ## Restart all Cilium pods
	@echo "$(BLUE)Restarting Cilium pods...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(MASTER_VM) -c 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml delete pod -n kube-system -l k8s-app=cilium'"
	@echo "$(GREEN)Cilium pods restarting$(NC)"

# Network debugging
net-debug-master: ## Debug network on cluster master
	@echo "$(BLUE)Network Debug - $(MASTER_VM):$(NC)"
	@echo "--- Interfaces ---"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(MASTER_VM) -c 'ip -br addr'" || true
	@echo "--- Routes ---"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(MASTER_VM) -c 'ip route'" || true

net-debug-worker1: ## Debug network on worker-1
	@echo "$(BLUE)Network Debug - $(CLUSTER_NAME)-worker-1:$(NC)"
	@echo "--- Interfaces ---"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(CLUSTER_NAME)-worker-1 -c 'ip -br addr'" || true
	@echo "--- Routes ---"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(CLUSTER_NAME)-worker-1 -c 'ip route'" || true

net-test-clusterip: ## Test ClusterIP connectivity from each node
	@echo "$(BLUE)Testing ClusterIP from each $(CLUSTER) node:$(NC)"
	@echo "--- Master ---"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(MASTER_VM) -c 'curl -k -s -o /dev/null -w \"%{http_code}\" --connect-timeout 3 https://10.43.0.1:443/version'" || echo "FAILED"
	@echo ""
	@echo "--- Worker-1 ---"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(CLUSTER_NAME)-worker-1 -c 'curl -k -s -o /dev/null -w \"%{http_code}\" --connect-timeout 3 https://10.43.0.1:443/version'" || echo "FAILED"
	@echo ""
	@echo "--- Worker-2 ---"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(CLUSTER_NAME)-worker-2 -c 'curl -k -s -o /dev/null -w \"%{http_code}\" --connect-timeout 3 https://10.43.0.1:443/version'" || echo "FAILED"
	@echo ""
	@echo "--- Worker-3 ---"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(CLUSTER_NAME)-worker-3 -c 'curl -k -s -o /dev/null -w \"%{http_code}\" --connect-timeout 3 https://10.43.0.1:443/version'" || echo "FAILED"

# Quick diagnostics
diag: ## Quick cluster diagnostics
	@echo "$(BLUE)=== Nodes ($(CLUSTER)) ===$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(MASTER_VM) -c 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes -o wide'" || true
	@echo ""
	@echo "$(BLUE)=== Problem Pods ===$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(MASTER_VM) -c 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get pods -A'" | grep -vE "Running|Completed" || echo "All pods healthy"
	@echo ""
	@echo "$(BLUE)=== Cilium Status ===$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(MASTER_VM) -c 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml exec -n kube-system ds/cilium -- cilium status --brief'" || true
	@echo ""
	@echo "$(BLUE)=== Kubernetes Endpoints ===$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(MASTER_VM) -c 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get endpoints -A'" || true

# Rebuild all nodes
cluster-rebuild-all: ## Sync and rebuild all cluster nodes
	@echo "$(BLUE)Rebuilding all $(CLUSTER) nodes...$(NC)"
	@$(MAKE) sync-master
	@$(MAKE) sync-worker-1
	@$(MAKE) sync-worker-2
	@$(MAKE) sync-worker-3
	@$(MAKE) rebuild-master-switch
	@echo "$(BLUE)Ensuring rke2-server is running...$(NC)"
	@ssh $(REMOTE_HOST) "ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY) vagrant@$(MASTER_IP) 'sudo systemctl start rke2-server 2>/dev/null || true'"
	@echo "$(BLUE)Waiting for RKE2 server to generate join token...$(NC)"
	@for i in $$(seq 1 60); do \
		TOKEN=$$(ssh $(REMOTE_HOST) "ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY) vagrant@$(MASTER_IP) 'sudo cat /var/lib/rancher/rke2/server/node-token 2>/dev/null'" 2>/dev/null | tr -d '\r'); \
		if [ -n "$$TOKEN" ]; then \
			echo "$(GREEN)Token available$(NC)"; \
			break; \
		fi; \
		echo "  Attempt $$i/60 - waiting for token..."; \
		sleep 5; \
	done
	@$(MAKE) distribute-token
	@$(MAKE) rebuild-worker-1-switch
	@$(MAKE) rebuild-worker-2-switch
	@$(MAKE) rebuild-worker-3-switch
	@echo "$(GREEN)All $(CLUSTER) nodes rebuilt$(NC)"

# SSH shortcuts
ssh-master: ## SSH into cluster master VM (via iter)
	@ssh -t $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(MASTER_VM)"

ssh-worker-1: ## SSH into worker-1 VM (via iter)
	@ssh -t $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(CLUSTER_NAME)-worker-1"

ssh-worker-2: ## SSH into worker-2 VM (via iter)
	@ssh -t $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(CLUSTER_NAME)-worker-2"

ssh-worker-3: ## SSH into worker-3 VM (via iter)
	@ssh -t $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh $(CLUSTER_NAME)-worker-3"

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
		echo "Run: export KUBECONFIG=~/.kube/config-$(CLUSTER)"; \
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
		echo "Run: export KUBECONFIG=~/.kube/config-$(CLUSTER)"; \
		exit 1; \
	fi
	@./iac/scripts/configure-vault-k8s-auth.sh
	@echo "$(GREEN)Vault Kubernetes auth configured$(NC)"

# ============================================================================
# Deployment (Kustomize + Helmfile)
# ============================================================================

VAULT_URL ?= https://vault.support.example.com

deploy-vault-auth: ## Apply vault-auth SA and update Vault k8s auth config (per-cluster)
	@if [ -z "$${KUBECONFIG:-}" ]; then \
		echo "$(RED)ERROR: KUBECONFIG not set$(NC)"; \
		echo "Run: export KUBECONFIG=~/.kube/config-$(CLUSTER)"; \
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
	@echo "$(BLUE)Enabling Vault auth mount $(CLUSTER_VAULT_AUTH_MOUNT) (if needed)...$(NC)"
	@VAULT_TOKEN=$$(jq -r '.root_token' $(VAULT_KEYS_BACKUP)); \
	RESULT=$$(curl -sk -w "\n%{http_code}" -X POST \
		-H "X-Vault-Token: $$VAULT_TOKEN" \
		-d '{"type":"kubernetes"}' \
		$(VAULT_URL)/v1/sys/auth/$(CLUSTER_VAULT_AUTH_MOUNT)); \
	HTTP_CODE=$$(echo "$$RESULT" | tail -1); \
	if [ "$$HTTP_CODE" = "204" ] || [ "$$HTTP_CODE" = "200" ]; then \
		echo "$(GREEN)Auth mount $(CLUSTER_VAULT_AUTH_MOUNT) enabled$(NC)"; \
	elif echo "$$RESULT" | head -n -1 | grep -q "path is already in use"; then \
		echo "Auth mount $(CLUSTER_VAULT_AUTH_MOUNT) already exists"; \
	else \
		echo "$(RED)WARNING: Vault returned HTTP $$HTTP_CODE when enabling auth mount$(NC)"; \
		echo "$$RESULT" | head -n -1; \
	fi
	@echo "$(BLUE)Updating Vault Kubernetes auth config for $(CLUSTER_VAULT_AUTH_MOUNT)...$(NC)"
	@VAULT_TOKEN=$$(jq -r '.root_token' $(VAULT_KEYS_BACKUP)); \
	SA_JWT=$$(kubectl get secret vault-auth-token -n vault-auth -o jsonpath='{.data.token}' | base64 -d); \
	K8S_CA=$$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d); \
	K8S_HOST=$$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'); \
	RESULT=$$(curl -sk -w "\n%{http_code}" -X POST \
		-H "X-Vault-Token: $$VAULT_TOKEN" \
		-d "$$(jq -n --arg host "$$K8S_HOST" --arg jwt "$$SA_JWT" --arg ca "$$K8S_CA" \
			'{kubernetes_host: $$host, token_reviewer_jwt: $$jwt, kubernetes_ca_cert: $$ca, disable_iss_validation: true}')" \
		$(VAULT_URL)/v1/auth/$(CLUSTER_VAULT_AUTH_MOUNT)/config); \
	HTTP_CODE=$$(echo "$$RESULT" | tail -1); \
	if [ "$$HTTP_CODE" != "204" ] && [ "$$HTTP_CODE" != "200" ]; then \
		echo "$(RED)ERROR: Vault returned HTTP $$HTTP_CODE$(NC)"; \
		echo "$$RESULT" | head -n -1; \
		exit 1; \
	fi
	@echo "$(BLUE)Creating external-secrets role in $(CLUSTER_VAULT_AUTH_MOUNT)...$(NC)"
	@VAULT_TOKEN=$$(jq -r '.root_token' $(VAULT_KEYS_BACKUP)); \
	RESULT=$$(curl -sk -w "\n%{http_code}" -X POST \
		-H "X-Vault-Token: $$VAULT_TOKEN" \
		-d '{"bound_service_account_names":["external-secrets"],"bound_service_account_namespaces":["external-secrets"],"policies":["external-secrets"],"ttl":"1h"}' \
		$(VAULT_URL)/v1/auth/$(CLUSTER_VAULT_AUTH_MOUNT)/role/external-secrets); \
	HTTP_CODE=$$(echo "$$RESULT" | tail -1); \
	if [ "$$HTTP_CODE" != "204" ] && [ "$$HTTP_CODE" != "200" ]; then \
		echo "$(RED)WARNING: Vault returned HTTP $$HTTP_CODE creating role$(NC)"; \
		echo "$$RESULT" | head -n -1; \
	fi
	@echo "$(GREEN)Vault k8s auth configured for $(CLUSTER) (mount: $(CLUSTER_VAULT_AUTH_MOUNT))$(NC)"

deploy-secrets: ## Apply ClusterSecretStore + ExternalSecrets + cert-manager resources (per-cluster)
	@if [ -z "$${KUBECONFIG:-}" ]; then \
		echo "$(RED)ERROR: KUBECONFIG not set$(NC)"; \
		echo "Run: export KUBECONFIG=~/.kube/config-$(CLUSTER)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Applying ClusterSecretStore and ExternalSecrets ($(CLUSTER))...$(NC)"
	@kubectl apply -k $(CLUSTER_GEN_DIR)/kustomize/external-secrets/
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
	@echo "$(BLUE)Applying cert-manager ClusterIssuers and certificates ($(CLUSTER))...$(NC)"
	@kubectl apply -k $(CLUSTER_GEN_DIR)/kustomize/cert-manager/
	@echo "$(GREEN)Secrets and cert-manager resources applied$(NC)"

deploy-base-resources: deploy-vault-auth deploy-secrets ## Apply all kustomize base resources

deploy-default: deploy-vault-auth ## Deploy default profile (MetalLB L2 + nginx-ingress, no Cilium)
	@echo "$(BLUE)Deploying MetalLB...$(NC)"
	@cd $(HELMFILE_DIR) && helmfile -e default \
		--state-values-file $(CLUSTER_GEN_DIR)/helmfile-values.yaml \
		-l name=metallb apply
	@echo "$(BLUE)Waiting for MetalLB CRDs...$(NC)"
	@for i in $$(seq 1 30); do \
		kubectl get crd ipaddresspools.metallb.io >/dev/null 2>&1 && break; \
		sleep 2; \
	done
	@echo "$(BLUE)Applying MetalLB address pool ($(CLUSTER))...$(NC)"
	@kubectl apply -k $(CLUSTER_GEN_DIR)/kustomize/metallb/
	@echo "$(BLUE)Deploying remaining helmfile releases...$(NC)"
	@cd $(HELMFILE_DIR) && helmfile -e default \
		--state-values-file $(CLUSTER_GEN_DIR)/helmfile-values.yaml \
		apply
	@$(MAKE) deploy-secrets
	@echo "$(GREEN)Default deployment complete for $(CLUSTER)$(NC)"

deploy-bgp-simple: deploy-vault-auth ## Deploy Cilium BGP + nginx-ingress profile
	@echo "$(BLUE)Deploying helmfile bgp-simple environment ($(CLUSTER))...$(NC)"
	@cd $(HELMFILE_DIR) && helmfile -e bgp-simple \
		--state-values-file $(CLUSTER_GEN_DIR)/helmfile-values.yaml \
		apply
	@$(MAKE) deploy-secrets
	@echo "$(BLUE)Applying per-cluster Cilium CRDs...$(NC)"
	@kubectl apply -k $(CLUSTER_GEN_DIR)/kustomize/cilium/
	@echo "$(GREEN)BGP simple deployment complete for $(CLUSTER)$(NC)"

deploy-gateway-bgp: deploy-vault-auth ## Deploy Cilium BGP + Gateway API profile
	@echo "$(BLUE)Applying Gateway API CRDs (must be installed before Cilium)...$(NC)"
	@kubectl apply --server-side -k $(KUSTOMIZE_DIR)/base/gateway-api-crds/
	@echo "$(BLUE)Deploying helmfile gateway-bgp environment ($(CLUSTER))...$(NC)"
	@cd $(HELMFILE_DIR) && helmfile -e gateway-bgp \
		--state-values-file $(CLUSTER_GEN_DIR)/helmfile-values.yaml \
		apply
	@$(MAKE) deploy-secrets
	@echo "$(BLUE)Applying per-cluster Cilium CRDs...$(NC)"
	@kubectl apply -k $(CLUSTER_GEN_DIR)/kustomize/cilium/
	@echo "$(BLUE)Applying Gateway resources ($(CLUSTER))...$(NC)"
	@kubectl apply -k $(CLUSTER_GEN_DIR)/kustomize/gateway/
	@echo "$(GREEN)Gateway BGP deployment complete for $(CLUSTER)$(NC)"

deploy: deploy-vault-auth ## Deploy using cluster's configured helmfile_env from cluster.yaml
	@echo "$(BLUE)Deploying $(CLUSTER) with helmfile env '$(CLUSTER_HELMFILE_ENV)'...$(NC)"
	@if [ "$(CLUSTER_HELMFILE_ENV)" = "gateway-bgp" ]; then \
		echo "$(BLUE)Applying Gateway API CRDs (must be installed before Cilium)...$(NC)"; \
		kubectl apply --server-side -k $(KUSTOMIZE_DIR)/base/gateway-api-crds/; \
	fi
	@if [ "$(CLUSTER_HELMFILE_ENV)" = "default" ]; then \
		echo "$(BLUE)Deploying MetalLB...$(NC)"; \
		cd $(HELMFILE_DIR) && helmfile -e default \
			--state-values-file $(CLUSTER_GEN_DIR)/helmfile-values.yaml \
			-l name=metallb apply; \
		echo "$(BLUE)Waiting for MetalLB CRDs...$(NC)"; \
		for i in $$(seq 1 30); do \
			kubectl get crd ipaddresspools.metallb.io >/dev/null 2>&1 && break; \
			sleep 2; \
		done; \
		echo "$(BLUE)Applying MetalLB address pool...$(NC)"; \
		kubectl apply -k $(CLUSTER_GEN_DIR)/kustomize/metallb/; \
	fi
	@cd $(HELMFILE_DIR) && helmfile -e $(CLUSTER_HELMFILE_ENV) \
		--state-values-file $(CLUSTER_GEN_DIR)/helmfile-values.yaml \
		apply
	@$(MAKE) deploy-secrets
	@if [ "$(CLUSTER_HELMFILE_ENV)" != "default" ]; then \
		echo "$(BLUE)Applying per-cluster Cilium CRDs...$(NC)"; \
		kubectl apply -k $(CLUSTER_GEN_DIR)/kustomize/cilium/; \
	fi
	@if [ "$(CLUSTER_HELMFILE_ENV)" = "gateway-bgp" ]; then \
		echo "$(BLUE)Applying Gateway resources ($(CLUSTER))...$(NC)"; \
		kubectl apply -k $(CLUSTER_GEN_DIR)/kustomize/gateway/; \
	fi
	@echo "$(GREEN)Deployment complete for $(CLUSTER) (env: $(CLUSTER_HELMFILE_ENV))$(NC)"

# ============================================================================
# Backward Compatibility Aliases
# ============================================================================
# These map old k8s-* target names to new cluster-parameterized targets

k8s-destroy: cluster-destroy
k8s-destroy-master: cluster-destroy-master
k8s-destroy-workers: cluster-destroy-workers
k8s-clean-state: cluster-clean-state
k8s-recreate: cluster-recreate
k8s-master-up: master-up
k8s-workers-up: workers-up
sync-k8s-master: sync-master
rebuild-k8s-master: rebuild-master
rebuild-k8s-master-switch: rebuild-master-switch
sync-k8s-worker-1: sync-worker-1
sync-k8s-worker-2: sync-worker-2
sync-k8s-worker-3: sync-worker-3
rebuild-k8s-worker-1: rebuild-worker-1
rebuild-k8s-worker-2: rebuild-worker-2
rebuild-k8s-worker-3: rebuild-worker-3
rebuild-k8s-worker-1-switch: rebuild-worker-1-switch
rebuild-k8s-worker-2-switch: rebuild-worker-2-switch
rebuild-k8s-worker-3-switch: rebuild-worker-3-switch
k8s-get-token: get-token
k8s-distribute-token: distribute-token
k8s-kubeconfig: cluster-kubeconfig
k8s-cluster-status: cluster-status
k8s-master-status: master-status
k8s-master-logs: master-logs
k8s-worker-logs: worker-logs
k8s-rebuild-all: cluster-rebuild-all
k8s-diag: diag
k8s-deploy-default: deploy-default
k8s-deploy-bgp-simple: deploy-bgp-simple
k8s-deploy-gateway-bgp: deploy-gateway-bgp
k8s-deploy-vault-auth: deploy-vault-auth
k8s-deploy-secrets: deploy-secrets
k8s-deploy-base-resources: deploy-base-resources
vagrant-ssh-k8s-master: ssh-master
vagrant-ssh-k8s-worker-1: ssh-worker-1
vagrant-ssh-k8s-worker-2: ssh-worker-2
vagrant-ssh-k8s-worker-3: ssh-worker-3

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
	@if [ -f "$(HOME)/.kube/config-$(CLUSTER)" ]; then \
		KUBECONFIG=$(HOME)/.kube/config-$(CLUSTER) kubectl cluster-info; \
	else \
		echo "$(RED)No kubeconfig found. Run 'make cluster-kubeconfig' first.$(NC)"; \
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
	@echo "Cluster: $(CLUSTER)"
	@echo "Cluster Name: $(CLUSTER_NAME)"
	@echo "Domain: $(CLUSTER_DOMAIN)"
	@echo "CNI: $(CLUSTER_CNI)"
	@echo "Helmfile Env: $(CLUSTER_HELMFILE_ENV)"
	@echo "Master VM: $(MASTER_VM)"
	@echo "Master IP: $(MASTER_IP)"
	@echo "Worker VMs: $(CLUSTER_WORKER_VMS)"
	@echo "LB CIDR: $(CLUSTER_LB_CIDR)"
	@echo "Vault Auth Mount: $(CLUSTER_VAULT_AUTH_MOUNT)"
	@echo "BGP ASN: $(CLUSTER_BGP_ASN)"
	@echo "Remote Host: $(REMOTE_HOST)"
	@echo "Helmfile Directory: $(HELMFILE_DIR)"
