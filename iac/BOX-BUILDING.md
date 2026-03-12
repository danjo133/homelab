# Building Custom NixOS Vagrant Boxes

This document explains how to build custom NixOS Vagrant boxes for use with the homelab infrastructure.

## Overview

Instead of using pre-built boxes from Vagrant Cloud, we build our own boxes using `nixos-generators`. This gives us:

1. **Full control** over the base system configuration
2. **Reproducibility** - same configuration produces same box
3. **Future compatibility** with `nixos-anywhere` for bare metal and cloud deployments
4. **Customization** - easy to add/modify base packages and services

## Prerequisites

You need `nixos-generate` installed. You can use it via Nix:

```bash
nix --extra-experimental-features nix-command --extra-experimental-features flakes shell nixpkgs#nixos-generators
```

Or if you have it installed globally, it's available directly.

## Building the Box

### Option 1: Using Make (Recommended)

```bash
make build-nix-box
```

This will:
1. Run the build script from the `iac/` directory
2. Generate the NixOS Vagrant box using the config in `nix-box-config.nix`
3. Output `nixos-25.11-vagrant.box` in the `iac/` directory

### Option 2: Manual Build

```bash
cd iac

# Enter the nix shell with nixos-generators
nix --extra-experimental-features nix-command --extra-experimental-features flakes shell nixpkgs#nixos-generators

# Inside the nix shell, run the build script
bash build-nix-box.sh
```

## Configuration

The box is configured via `iac/nix-box-config.nix`, which includes:

- **DHCP networking** - automatic network configuration
- **SSH server** - enabled with root and vagrant user access
- **Vagrant user** - standard user with SSH key and passwordless sudo
- **Essential packages** - git, curl, vim, etc.
- **Serial console** - for debugging via QEMU serial port

### Customizing the Box

Edit `iac/nix-box-config.nix` to:
- Add more system packages
- Configure additional system services
- Change networking settings
- Add custom configurations

Then rebuild the box with `make build-nix-box`.

## Using the Box with Vagrant

The `Vagrantfile` in the `iac/` directory is configured to use the local box. Once built, you can bring up VMs:

```bash
cd iac
vagrant up
```

This will create:
- `support` - supporting systems VM (Vault, Harbor, MinIO, NFS)
- `k8s-master` - Kubernetes master node
- `k8s-worker-1`, `k8s-worker-2`, `k8s-worker-3` - Kubernetes worker nodes

## Box Specifications

Each VM is configured with:

- **Memory**: 8GB RAM
- **CPUs**: 4 cores
- **Network**: DHCP on public network (bridge mode)
- **Storage**: VirtualBox default (grows as needed)

## Future Use with nixos-anywhere

The configuration in `nix-box-config.nix` is designed to be a workstation that can later be extended for:

1. **Cloud deployments** (AWS, GCP, Azure) using `nixos-anywhere`
2. **Bare metal installations** with custom hardware configurations
3. **MSP installations** with remote management capabilities

The modular approach means we can:
- Share common base configuration
- Add provider-specific overlays (cloud, bare metal, etc.)
- Maintain a single source of truth for system state

## Troubleshooting

### Box build fails with "nixos-generators not found"

Install it with:
```bash
nix shell nixpkgs#nixos-generators
```

Then try building again.

### Vagrant says "box not found"

Ensure the box file exists:
```bash
ls -la iac/nixos-25.11-vagrant.box
```

If it doesn't exist, rebuild with `make build-nix-box`.

### Box is too large or too small

Edit `nix-box-config.nix` to adjust:
- Installed packages (affects size)
- Boot configuration
- System services

Then rebuild.

## References

- [nixos-generators GitHub](https://github.com/nix-community/nixos-generators)
- [NixOS Manual - Vagrant](https://nixos.org/manual/nixos/stable/index.html#sec-running-nixos)
- [nixos-anywhere Documentation](https://github.com/nix-community/nixos-anywhere)
