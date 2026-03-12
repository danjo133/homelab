{
  description = "Kubernetes Homelab Infrastructure - Nix Flake";
  
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    
    # Development tools
    devenv.url = "github:cachix/devenv";
    
    # NixOS anywhere for remote system configuration
    nixos-anywhere.url = "github:nix-community/nixos-anywhere";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, flake-utils, devenv, nixos-anywhere }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        pkgs-unstable = nixpkgs-unstable.legacyPackages.${system};
      in
      {
        # Development environment
        devShells.default = pkgs.mkShell {
          name = "kubernetes-homelab";
          
          buildInputs = with pkgs; [
            # Infrastructure tools
            vagrant
            virtualbox
            ansible
            
            # Kubernetes tools
            kubectl
            helm
            helmfile
            kustomize
            kubeseal
            
            # Container and image tools
            docker
            containerd
            skopeo
            crane
            
            # Container scanning
            trivy
            grype
            
            # Nix tools
            nix
            nixos-anywhere
            nixpkgs-fmt
            
            # Development utilities
            git
            curl
            wget
            jq
            yq
            jinja2
            
            # Documentation
            markdown
            mdl
            
            # CI/CD
            pre-commit
            renovate
            
            # Cloud tools
            aws-cli
            
            # Package managers
            nodejs
            python3
            python3Packages.pyyaml
            python3Packages.jinja2
            python3Packages.ruamel-yaml
            
            # Terminal utilities
            tmux
            vim
            openssh
            
            # Debugging
            dig
            netcat
            tcpdump
            htop
            
            # Terraform/IaC (optional)
            # terraform
            # terragrunt
          ];
          
          shellHook = ''
            echo "Welcome to Kubernetes Homelab Development Environment"
            echo "Available tools:"
            echo "  - Vagrant for VM management"
            echo "  - Kubernetes tools (kubectl, helm, kustomize)"
            echo "  - Container tools (docker, trivy, grype)"
            echo "  - Nix tools and nixos-anywhere"
            echo ""
            echo "Useful commands:"
            echo "  make help              - Show Makefile targets"
            echo "  make up                - Bring up VMs"
            echo "  make validate          - Validate configurations"
            echo "  make test              - Run tests"
            echo ""
          '';
        };
        
        # VM configuration packages
        packages = {
          # Supporting systems VM (Vault, Harbor, MinIO, NFS)
          supporting-systems-config = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [ ./iac/provision/nix/supporting-systems/configuration.nix ];
          };
          
          # Kubernetes master node
          k8s-master-config = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [ ./iac/provision/nix/k8s-master/configuration.nix ];
          };
          
          # Kubernetes worker node
          k8s-worker-config = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [ ./iac/provision/nix/k8s-worker/configuration.nix ];
          };
        };
        
        # Development apps
        apps = {
          # Install Renovate bot
          renovate = {
            type = "app";
            program = "${pkgs-unstable.renovate}/bin/renovate";
          };
          
          # Run Trivy scans
          trivy = {
            type = "app";
            program = "${trivy}/bin/trivy";
          };
        };
      }
    ) // {
      # NixOS modules for VM configurations
      nixosModules = {
        supporting-systems = import ./iac/provision/nix/supporting-systems/module.nix;
        kubernetes-master = import ./iac/provision/nix/k8s-master/module.nix;
        kubernetes-worker = import ./iac/provision/nix/k8s-worker/module.nix;
      };
    };
}
