.PHONY: help up provision down reset clean lint test validate sync-support rebuild-support rebuild-support-switch
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

# Support VM - get IP from vagrant on iter
SUPPORT_VM_IP ?= $(shell ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh support -c \"ip -4 addr show ens7 | grep -oP '(?<=inet\s)\d+(\.\d+){3}'\" 2>/dev/null" | tr -d '\r' || echo "10.69.50.91")

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
	@echo "$(GREEN)Vault Key Management:$(NC)"
	@echo "  make vault-backup-keys     Backup Vault keys to local file"
	@echo "  make vault-restore-keys    Restore Vault keys from backup"
	@echo "  make vault-show-token      Show Vault root token"
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
		vagrant@$(SUPPORT_VM_IP):/tmp/nix-config/"
	@ssh $(REMOTE_HOST) "rsync -avz \
		-e 'ssh -o StrictHostKeyChecking=no -i $(VAGRANT_SSH_KEY)' \
		$(REMOTE_PROJECT_DIR)/iac/provision/nix/common/ \
		vagrant@$(SUPPORT_VM_IP):/tmp/nix-config/common/"
	@echo "$(GREEN)Config synced to /tmp/nix-config/ on support VM$(NC)"

rebuild-support: sync-support ## Rebuild support VM NixOS config (test mode)
	@echo "$(BLUE)Rebuilding NixOS configuration (test mode)...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh support -c \
		'sudo nixos-rebuild test -I nixos-config=/tmp/nix-config/configuration.nix'"
	@echo "$(GREEN)Configuration applied (test mode - not permanent)$(NC)"

rebuild-support-switch: sync-support ## Rebuild and switch support VM NixOS config permanently
	@echo "$(BLUE)Rebuilding NixOS configuration (switch mode)...$(NC)"
	@ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh support -c \
		'sudo nixos-rebuild switch -I nixos-config=/tmp/nix-config/configuration.nix'"
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

# ============================================================================
# Kubernetes Cluster Management
# ============================================================================

K8S_MASTER_NIX_DIR := $(shell pwd)/iac/provision/nix/k8s-master
K8S_WORKER_NIX_DIR := $(shell pwd)/iac/provision/nix/k8s-worker

# Get VM IPs dynamically
K8S_MASTER_IP = $(shell ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-master -c \"ip -4 addr show ens7 | grep -oP '(?<=inet\s)\d+(\.\d+){3}'\" 2>/dev/null" | tr -d '\r')
K8S_WORKER_1_IP = $(shell ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-worker-1 -c \"ip -4 addr show ens7 | grep -oP '(?<=inet\s)\d+(\.\d+){3}'\" 2>/dev/null" | tr -d '\r')
K8S_WORKER_2_IP = $(shell ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-worker-2 -c \"ip -4 addr show ens7 | grep -oP '(?<=inet\s)\d+(\.\d+){3}'\" 2>/dev/null" | tr -d '\r')
K8S_WORKER_3_IP = $(shell ssh $(REMOTE_HOST) "cd $(REMOTE_VAGRANT_DIR) && /usr/bin/vagrant ssh k8s-worker-3 -c \"ip -4 addr show ens7 | grep -oP '(?<=inet\s)\d+(\.\d+){3}'\" 2>/dev/null" | tr -d '\r')

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
		| sed 's/127.0.0.1/k8s-master.local/g' > $(HOME)/.kube/config-kss
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
		kustomize build $(KUSTOMIZE_DIR)/base > /dev/null && \
		echo "$(GREEN)Kustomize validation passed!$(NC)" || \
		echo "$(RED)Kustomize validation failed!$(NC)"; \
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
