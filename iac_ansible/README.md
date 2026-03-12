# RKE2 Vagrant Kubernetes Lab

This repository contains scaffolding to provision an RKE2 (Rancher Kubernetes Engine v2) cluster using Vagrant on a workstation running Arch Linux.

Goal: a reproducible, bridge-networked lab cluster with 1 master and 3 workers suitable for experimenting with Cilium + Tetragon and BGP routing.

Files added:
- `Vagrantfile` - defines VMs and networks
- `provision/` - provisioning scripts for RKE2 server/agent
- `scripts/` - helper scripts
- `docs/ARCHITECTURE.md` - architecture overview
- `docs/SPEC-KIT.md` - spec kit and requirements
- `docs/TODO.md` - human-readable todo list

Next steps: customize bridge name, run `vagrant up` to create VMs, then follow `docs/ARCHITECTURE.md` for networking and BGP setup.
