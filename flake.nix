{
  description = "KSS — Kubernetes homelab infrastructure-as-code";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
      in
      {
        devShells.default = pkgs.mkShell {
          name = "kss";

          buildInputs = with pkgs; [
            # Task runner
            just

            # VM management
            vagrant

            # Kubernetes
            kubectl
            kubernetes-helm
            helmfile
            kustomize
            kubelogin-oidc

            # IaC
            opentofu
            tflint

            # Secrets & encryption
            sops
            age

            # Data wrangling & templating
            jq
            yq-go
            gomplate

            # Container tools
            skopeo
            crane

            # Security scanning
            trivy
            grype

            # Network & transfer
            openssh
            rsync
            curl

            # Linting & quality
            pre-commit
            shellcheck
            yamllint
          ];

          shellHook = ''
            if [ -z "''${KSS_CLUSTER:-}" ]; then
              echo "Hint: export KSS_CLUSTER=kss  (required for cluster commands)"
            else
              echo "KSS_CLUSTER=$KSS_CLUSTER"
            fi
            echo "Run 'just help' to see available commands."
          '';
        };
      }
    );
}
