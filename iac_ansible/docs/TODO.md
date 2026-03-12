# Human-readable TODO

1. Configure host bridge and ensure `BRIDGE` env var is set or `br0` exists.
2. Confirm Vagrant provider (VirtualBox or libvirt) is installed and working on Arch.
3. Run `vagrant up` to provision the master and workers.
4. On master VM run `/vagrant/scripts/write_server_ip.sh <MASTER_IP>` to publish the server IP.
5. Wait for agents to join (they read `/vagrant/rke2_token` and `/vagrant/server_ip`).
6. Copy `/vagrant/kubeconfig` to host ~/.kube/config for kubectl access.
7. Deploy Cilium with Tetragon using Helm (documented in SPEC-KIT).
8. Configure BGP: either MetalLB in BGP mode or a cluster BGP speaker and peer with UniFi.
9. Harden cluster: RBAC, PSP/PSA, OPA, Tetragon policies.

Note: The current scaffolding uses Ubuntu 22.04 generic box by default; change `BOX` env var in `Vagrantfile` to use a preferred image.
