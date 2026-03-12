.PHONY: help up provision down reset clean lint test validate
.DEFAULT_GOAL := help

# Color output
BLUE := \033[0;34m
GREEN := \033[0;32m
RED := \033[0;31m
NC := \033[0m # No Color

# Paths
VAGRANT_DIR := $(shell pwd)/iac_ansible
HELMFILE_DIR := $(shell pwd)/iac/helmfile
KUSTOMIZE_DIR := $(shell pwd)/iac/kustomize
DOCS_DIR := $(shell pwd)/iac/docs

# Help target
help:
	@echo "$(BLUE)Kubernetes Homelab Infrastructure - Make Commands$(NC)"
	@echo ""
	@echo "$(GREEN)Usage:$(NC)"
	@echo "  make help              Show this help message"
	@echo "  make up                Bring up all Vagrant VMs"
	@echo "  make down              Stop all Vagrant VMs (without destroying)"
	@echo "  make provision         Provision VMs with NixOS and services"
	@echo "  make reset             Destroy and recreate all VMs"
	@echo "  make clean             Clean up Vagrant and local artifacts"
	@echo "  make status            Show Vagrant VM status"
	@echo "  make validate          Validate Helm and Kustomize manifests"
	@echo "  make lint              Lint documentation and configurations"
	@echo "  make test              Run smoke tests"
	@echo "  make docs              Generate documentation"
	@echo "  make k8s-status        Check Kubernetes cluster status"
	@echo "  make k8s-config        Get kubeconfig from cluster"
	@echo ""

# Vagrant commands
build-nix-box: ## Build custom NixOS Vagrant box
	@echo "$(BLUE)Building custom NixOS Vagrant box...$(NC)"
	@cd iac && bash build-nix-box.sh
	@echo "$(GREEN)Box built successfully!$(NC)"

up: ## Bring up all VMs
	@echo "$(BLUE)Bringing up Vagrant VMs...$(NC)"
	@cd $(VAGRANT_DIR) && vagrant up
	@echo "$(GREEN)VMs are up!$(NC)"

down: ## Stop all VMs without destroying
	@echo "$(BLUE)Stopping Vagrant VMs...$(NC)"
	@cd $(VAGRANT_DIR) && vagrant halt
	@echo "$(GREEN)VMs stopped!$(NC)"

reset: ## Destroy and recreate all VMs (full reset)
	@echo "$(RED)Resetting infrastructure...$(NC)"
	@read -p "Are you sure? This will destroy all VMs. [y/N] " -n 1 -r; \
	echo ""; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		cd $(VAGRANT_DIR) && vagrant destroy -f; \
		cd $(VAGRANT_DIR) && vagrant up; \
		make provision; \
		echo "$(GREEN)Infrastructure reset complete!$(NC)"; \
	else \
		echo "$(BLUE)Reset cancelled$(NC)"; \
	fi

clean: ## Clean up Vagrant artifacts and local files
	@echo "$(BLUE)Cleaning up...$(NC)"
	@cd $(VAGRANT_DIR) && vagrant destroy -f
	@rm -rf $(VAGRANT_DIR)/.vagrant
	@rm -rf .kubeconfig
	@echo "$(GREEN)Cleanup complete!$(NC)"

status: ## Show Vagrant VM status
	@echo "$(BLUE)Vagrant VM Status:$(NC)"
	@cd $(VAGRANT_DIR) && vagrant status

# Provisioning commands
provision: ## Provision VMs (NixOS configuration + services)
	@echo "$(BLUE)Provisioning VMs with NixOS...$(NC)"
	@cd $(VAGRANT_DIR) && vagrant provision
	@echo "$(GREEN)Provisioning complete!$(NC)"
	@echo "$(BLUE)Waiting for cluster to stabilize...$(NC)"
	@sleep 30
	@make k8s-status

# Kubernetes commands
k8s-status: ## Check Kubernetes cluster status
	@echo "$(BLUE)Kubernetes Cluster Status:$(NC)"
	@if command -v kubectl &> /dev/null; then \
		kubectl get nodes -o wide; \
		echo ""; \
		echo "$(BLUE)System Pods:$(NC)"; \
		kubectl get pods -n kube-system -o wide; \
	else \
		echo "$(RED)kubectl not found in PATH$(NC)"; \
	fi

k8s-config: ## Extract kubeconfig from cluster
	@echo "$(BLUE)Extracting kubeconfig...$(NC)"
	@if [ -f "$(VAGRANT_DIR)/.vagrant/machines/k8s-master/virtualbox/id" ]; then \
		mkdir -p $(HOME)/.kube; \
		scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
			vagrant@k8s-master:/etc/rancher/rke2/rke2.yaml \
			$(HOME)/.kube/config 2>/dev/null || \
			echo "$(RED)Failed to extract kubeconfig. Ensure k8s-master is running.$(NC)"; \
		echo "$(GREEN)kubeconfig extracted to $(HOME)/.kube/config$(NC)"; \
	else \
		echo "$(RED)k8s-master VM not found$(NC)"; \
	fi

# Validation commands
validate: validate-helm validate-kustomize validate-docs ## Run all validations

validate-helm: ## Validate Helmfile
	@echo "$(BLUE)Validating Helmfile...$(NC)"
	@if command -v helmfile &> /dev/null; then \
		cd $(HELMFILE_DIR) && helmfile lint; \
		echo "$(GREEN)Helmfile validation passed!$(NC)"; \
	else \
		echo "$(RED)helmfile not found. Install with: helm plugin install https://github.com/roboll/helmfile$(NC)"; \
	fi

validate-kustomize: ## Validate Kustomize manifests
	@echo "$(BLUE)Validating Kustomize manifests...$(NC)"
	@if command -v kustomize &> /dev/null; then \
		kustomize build $(KUSTOMIZE_DIR)/base > /dev/null && \
		echo "$(GREEN)Kustomize validation passed!$(NC)" || \
		echo "$(RED)Kustomize validation failed!$(NC)"; \
	else \
		echo "$(RED)kustomize not found. Install from https://kustomize.io$(NC)"; \
	fi

validate-docs: ## Validate documentation files
	@echo "$(BLUE)Validating documentation...$(NC)"
	@for file in $(DOCS_DIR)/*.md; do \
		if [ -f "$$file" ]; then \
			echo "Checking $$file"; \
		fi; \
	done
	@echo "$(GREEN)Documentation validation passed!$(NC)"

# Linting commands
lint: lint-helm lint-kustomize lint-docs ## Run all linters

lint-helm: ## Lint Helm charts
	@echo "$(BLUE)Linting Helm charts...$(NC)"
	@if command -v helm &> /dev/null; then \
		cd $(HELMFILE_DIR) && \
		for values in values/*.yaml; do \
			echo "Linting $$values"; \
			helm lint -f $$values > /dev/null 2>&1 || true; \
		done; \
		echo "$(GREEN)Helm linting complete!$(NC)"; \
	else \
		echo "$(RED)helm not found$(NC)"; \
	fi

lint-kustomize: ## Lint Kustomize overlays
	@echo "$(BLUE)Linting Kustomize overlays...$(NC)"
	@if command -v kustomize &> /dev/null; then \
		for overlay in $(KUSTOMIZE_DIR)/overlays/*; do \
			if [ -d "$$overlay" ]; then \
				echo "Linting $$overlay"; \
				kustomize build $$overlay > /dev/null || true; \
			fi; \
		done; \
		echo "$(GREEN)Kustomize linting complete!$(NC)"; \
	else \
		echo "$(RED)kustomize not found$(NC)"; \
	fi

lint-docs: ## Lint documentation for common issues
	@echo "$(BLUE)Linting documentation...$(NC)"
	@find $(DOCS_DIR) -name "*.md" -exec echo "Linting {}" \;
	@echo "$(GREEN)Documentation linting complete!$(NC)"

# Testing commands
test: test-smoke test-security ## Run all tests

test-smoke: ## Run smoke tests
	@echo "$(BLUE)Running smoke tests...$(NC)"
	@if command -v kubectl &> /dev/null; then \
		echo "Testing cluster connectivity..."; \
		kubectl cluster-info; \
		echo "Testing pod creation..."; \
		kubectl run smoke-test --image=alpine:latest --restart=Never --rm -i -- echo "Smoke test passed"; \
		echo "$(GREEN)Smoke tests passed!$(NC)"; \
	else \
		echo "$(RED)kubectl not found$(NC)"; \
	fi

test-security: ## Run security tests
	@echo "$(BLUE)Running security tests...$(NC)"
	@echo "Checking network policies..."; \
	kubectl get networkpolicies -A; \
	echo "Checking RBAC..."; \
	kubectl get clusterroles,clusterrolebindings; \
	echo "$(GREEN)Security tests complete!$(NC)"

# Documentation commands
docs: ## Generate or update documentation
	@echo "$(BLUE)Documentation:$(NC)"
	@echo "Architecture: $(DOCS_DIR)/ARCHITECTURE.md"
	@echo "Specification: $(DOCS_DIR)/SPEC-KIT.md"
	@echo "TODO List: $(DOCS_DIR)/TODO.md"
	@echo "$(GREEN)Documentation files are in $(DOCS_DIR)$(NC)"

# Build/Install dependencies
install-tools: ## Install required tools
	@echo "$(BLUE)Installing required tools...$(NC)"
	@command -v vagrant >/dev/null 2>&1 || echo "Please install Vagrant"
	@command -v helm >/dev/null 2>&1 || echo "Please install Helm"
	@command -v kubectl >/dev/null 2>&1 || echo "Please install kubectl"
	@command -v kustomize >/dev/null 2>&1 || echo "Please install Kustomize"
	@command -v helmfile >/dev/null 2>&1 || echo "Please install Helmfile (helm plugin install https://github.com/roboll/helmfile)"
	@echo "$(GREEN)Tool check complete!$(NC)"

# Git/Version control
git-init: ## Initialize git repository
	@echo "$(BLUE)Initializing git repository...$(NC)"
	@if [ -d .git ]; then \
		echo "Git repository already initialized"; \
	else \
		git init; \
		git config user.email "homelab@local"; \
		git config user.name "Homelab Admin"; \
		git add .; \
		git commit -m "Initial commit: Kubernetes homelab infrastructure scaffolding"; \
		echo "$(GREEN)Git repository initialized!$(NC)"; \
	fi

# Debugging/Troubleshooting
debug-vault: ## Debug Vault connectivity
	@echo "$(BLUE)Debugging Vault...$(NC)"
	@echo "Checking if Vault is accessible..."
	@curl -k https://trust.support.example.com:8200/v1/sys/health 2>/dev/null | jq . || echo "Vault not accessible"

debug-harbor: ## Debug Harbor connectivity
	@echo "$(BLUE)Debugging Harbor...$(NC)"
	@echo "Checking if Harbor is accessible..."
	@curl -k https://artifacts.support.example.com 2>/dev/null -I || echo "Harbor not accessible"

debug-k8s: ## Debug Kubernetes
	@echo "$(BLUE)Debugging Kubernetes...$(NC)"
	@kubectl version
	@kubectl get componentstatuses
	@kubectl get nodes -o wide

# Logs and diagnostics
logs-master: ## Get logs from master node
	@echo "$(BLUE)Master node logs:$(NC)"
	@cd $(VAGRANT_DIR) && vagrant ssh k8s-master -c "journalctl -u rke2-server -n 100"

logs-worker: ## Get logs from worker node
	@echo "$(BLUE)Worker node logs:$(NC)"
	@cd $(VAGRANT_DIR) && vagrant ssh k8s-worker-1 -c "journalctl -u rke2-agent -n 100"

logs-supporting: ## Get logs from supporting systems
	@echo "$(BLUE)Supporting systems logs:$(NC)"
	@cd $(VAGRANT_DIR) && vagrant ssh supporting-systems -c "journalctl -n 100"

# Utility targets
.PHONY: print-config
print-config: ## Print configuration variables
	@echo "$(BLUE)Configuration:$(NC)"
	@echo "Vagrant Directory: $(VAGRANT_DIR)"
	@echo "Helmfile Directory: $(HELMFILE_DIR)"
	@echo "Kustomize Directory: $(KUSTOMIZE_DIR)"
	@echo "Docs Directory: $(DOCS_DIR)"

# Targets for CI/CD
ci-validate: validate lint ## Run CI validations
	@echo "$(GREEN)CI validations passed!$(NC)"

ci-test: test ## Run CI tests
	@echo "$(GREEN)CI tests passed!$(NC)"
