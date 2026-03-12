# Phase 2: RKE2 Kubernetes Cluster - Lessons Learned

This document captures the assumptions, issues encountered, and solutions discovered while deploying an RKE2 Kubernetes cluster on NixOS VMs. It serves as both a tutorial and a troubleshooting guide for future reference.

## Overview

**Goal**: Deploy a 4-node RKE2 Kubernetes cluster (1 master + 3 workers) on NixOS VMs managed by Vagrant/libvirt.

**Final Result**: Successfully deployed cluster with all nodes joined. Nodes show "NotReady" status which is expected because CNI (Cilium) will be installed in Phase 3.

---

## Architecture Assumptions

### 1. Network Configuration
- **Assumption**: VMs have two network interfaces:
  - `ens6` (192.168.121.x): Libvirt NAT for Vagrant SSH management only
  - `ens7` (10.69.50.x): VLAN 50 bridged network for cluster traffic and internet
- **Reality**: This worked as expected. The VLAN 50 interface is used for all Kubernetes traffic.

### 2. DNS/Hostname Resolution
- **Assumption**: mDNS (Avahi) would allow nodes to resolve each other via `.local` hostnames (e.g., `k8s-master.local`)
- **Reality**: mDNS works for direct connections (curl, SSH) but **fails inside RKE2's internal load balancer**
- **Solution**: Use IP addresses directly in RKE2 agent configuration, or resolve hostname to IP before writing config

### 3. NixOS File System Layout
- **Assumption**: RKE2 would install to `/usr/local/bin/` like on standard Linux
- **Reality**: NixOS has a read-only `/usr/local`, so RKE2 installs to `/opt/rke2/bin/`
- **Solution**: Update systemd service `ExecStart` paths to use `/opt/rke2/bin/rke2`

### 4. Systemd Unit Installation
- **Assumption**: RKE2 installer would create its own systemd units
- **Reality**: NixOS has read-only `/etc/systemd/system/`, so the installer fails to copy units
- **Solution**: Define systemd services declaratively in NixOS configuration (which we were already doing)

---

## Issues Encountered and Solutions

### Issue 1: RKE2 Binary Path Mismatch

**Symptom**:
```
rke2-agent.service: Unable to locate executable '/usr/local/bin/rke2': No such file or directory
```

**Cause**: NixOS has a read-only `/usr/local` directory. The RKE2 installer detects this and installs to `/opt/rke2` instead.

**Solution**: Update the systemd service in `rke2-agent.nix`:
```nix
# Before (wrong)
ExecStart = "/usr/local/bin/rke2 agent";

# After (correct for NixOS)
ExecStart = "/opt/rke2/bin/rke2 agent";
```

**Note**: The master uses `/usr/local/bin/rke2` because the install script behavior differs slightly. Check actual install location on each node type.

---

### Issue 2: mDNS Resolution in RKE2 Load Balancer

**Symptom**:
```
failed to get CA certs: Get "https://127.0.0.1:6444/cacerts": read tcp 127.0.0.1:xxxxx->127.0.0.1:6444: read: connection reset by peer
```

**Cause**: RKE2 agent runs an internal TCP load balancer on `127.0.0.1:6444` that proxies to the server. This load balancer couldn't resolve `k8s-master.local` via mDNS, even though direct `curl` commands worked fine.

**Debugging Steps**:
1. Verified direct connectivity works:
   ```bash
   curl -k https://k8s-master.local:9345/cacerts  # Works!
   ```
2. Checked load balancer was listening:
   ```bash
   ss -tlnp | grep 6444  # Shows rke2 listening
   ```
3. Checked agent logs showing load balancer had empty server list:
   ```
   Running load balancer rke2-agent-load-balancer 127.0.0.1:6444 -> [] [default: k8s-master.local:9345]
   ```

**Solution**: Use IP address instead of hostname in `/etc/rancher/rke2/config.yaml`:
```yaml
# Before (fails)
server: https://k8s-master.local:9345

# After (works)
server: https://10.69.50.142:9345
```

**Better Solution** (implemented in code): Resolve hostname to IP at configuration time:
```bash
MASTER_IP=$(getent hosts k8s-master.local | awk '{print $1}' | head -1)
# Then use $MASTER_IP in config
```

---

### Issue 3: RKE2 Install Script Missing Dependencies

**Symptom**:
```
/tmp/rke2-install.sh: line 93: mountpoint: command not found
/tmp/rke2-install.sh: line 302: sed: command not found
/tmp/rke2-install.sh: line 310: awk: command not found
```

**Cause**: The RKE2 install script (from `https://get.rke2.io`) expects standard Unix tools in PATH. NixOS doesn't have these in the default PATH for systemd services.

**Solution**: Add required packages to the install script's PATH:
```nix
export PATH="${lib.makeBinPath [
  pkgs.curl
  pkgs.gnutar
  pkgs.gzip
  pkgs.coreutils
  pkgs.bash
  pkgs.gnused      # for sed
  pkgs.util-linux  # for mountpoint
  pkgs.gnugrep     # for grep
  pkgs.findutils   # for find
  pkgs.gawk        # for awk
  pkgs.diffutils   # for diff
]}"
```

**Alternative Solution** (used for workers 2 & 3): Install RKE2 manually with system PATH:
```bash
sudo bash -c "
  export PATH=/run/current-system/sw/bin:\$PATH
  curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION=v1.31.4+rke2r1 INSTALL_RKE2_TYPE=agent sh -
"
```

---

### Issue 4: NixOS Rebuild Conflicts

**Symptom**:
```
Failed to start transient service unit: Unit nixos-rebuild-switch-to-configuration.service was already loaded or has a fragment file.
```

**Cause**: A previous `nixos-rebuild switch` left a stale systemd transient unit.

**Solutions**:
1. Reset failed services and retry:
   ```bash
   sudo systemctl reset-failed
   sudo nixos-rebuild switch -I nixos-config=/path/to/config
   ```

2. Run switch-to-configuration directly:
   ```bash
   sudo /nix/store/<hash>-nixos-system-.../bin/switch-to-configuration switch
   ```

3. Reboot the VM (most reliable):
   ```bash
   sudo reboot
   ```

---

### Issue 5: NixOS Config Sync Path Structure

**Symptom**: `nixos-rebuild` couldn't find configuration file.

**Cause**: The Makefile syncs multiple directories to `/tmp/nix-config/`:
```
/tmp/nix-config/
├── k8s-common/
├── k8s-worker/
└── k8s-worker-1/  (or -2, -3)
```

The configuration.nix for each worker is in its numbered directory and uses relative imports.

**Solution**: Specify the correct path for nixos-rebuild:
```bash
# For worker-1:
sudo nixos-rebuild switch -I nixos-config=/tmp/nix-config/k8s-worker-1/configuration.nix

# For worker-2:
sudo nixos-rebuild switch -I nixos-config=/tmp/nix-config/k8s-worker-2/configuration.nix
```

---

### Issue 6: Port Range Syntax in NixOS Firewall

**Symptom**: NixOS evaluation error for firewall configuration.

**Cause**: Invalid syntax for port ranges in `allowedTCPPorts`.

**Solution**: Use `allowedTCPPortRanges` for ranges:
```nix
# Wrong
allowedTCPPorts = [ 22 10250 30000-32767 ];

# Correct
allowedTCPPorts = [ 22 10250 ];
allowedTCPPortRanges = [
  { from = 30000; to = 32767; }
];
```

---

## Deployment Workflow That Works

### Step 1: Start Master VM
```bash
make k8s-master-up
```

### Step 2: Sync and Rebuild Master Config
```bash
make sync-k8s-master
make rebuild-k8s-master-switch
```

### Step 3: Wait for RKE2 Server to Initialize
```bash
# Check status
ssh hypervisor "vagrant ssh k8s-master -c 'sudo systemctl status rke2-server'"

# Verify node is registered (will show NotReady without CNI)
ssh hypervisor "vagrant ssh k8s-master -c 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes'"
```

### Step 4: Get Join Token
```bash
# Token is at /var/lib/rancher/rke2/server/node-token on master
make k8s-distribute-token
```

### Step 5: Start Worker VMs
```bash
make k8s-workers-up
```

### Step 6: Configure Workers with IP Address
**Critical**: Due to mDNS issue, manually set the config with IP:
```bash
# On each worker:
sudo tee /etc/rancher/rke2/config.yaml << EOF
server: https://10.69.50.142:9345  # Use actual master IP
token: <token-from-master>
EOF
sudo touch /etc/rancher/rke2/.token-configured
```

### Step 7: Install RKE2 on Workers (if not already installed)
```bash
sudo bash -c "
  export PATH=/run/current-system/sw/bin:\$PATH
  curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION=v1.31.4+rke2r1 INSTALL_RKE2_TYPE=agent sh -
  touch /var/lib/rancher/rke2/.installed
"
```

### Step 8: Sync and Rebuild Worker Configs
```bash
make sync-k8s-worker-1 && make rebuild-k8s-worker-1
# Or reboot for clean state:
ssh hypervisor "vagrant ssh k8s-worker-1 -c 'sudo reboot'"
```

### Step 9: Verify Cluster
```bash
ssh hypervisor "vagrant ssh k8s-master -c 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes -o wide'"
```

---

## Key Takeaways

### 1. NixOS is Different
- Read-only system directories (`/usr/local`, `/etc/systemd/system`)
- Packages must be explicitly added to PATH in scripts
- Declarative configuration is preferred over imperative installation

### 2. mDNS Has Limitations
- Works for user-space applications
- May not work inside containerized or sandboxed processes
- When in doubt, use IP addresses

### 3. RKE2 Install Script Assumptions
- Expects standard FHS Linux layout
- Needs many common Unix tools in PATH
- Tries to install systemd units (fails on NixOS, but that's OK)

### 4. Debugging Approach
1. Check service status: `systemctl status <service>`
2. Check logs: `journalctl -u <service> --no-pager`
3. Test connectivity manually: `curl`, `ping`, `getent hosts`
4. Check file existence: `ls -la /path/to/expected/file`
5. Verify PATH in scripts: `export PATH=... && which <command>`

### 5. Recovery Strategies
- `systemctl reset-failed` to clear stuck services
- `sudo reboot` for clean state after config changes
- Manual installation as fallback when automated fails

---

## Files Modified During Phase 2

| File | Changes |
|------|---------|
| `iac/provision/nix/k8s-worker/modules/rke2-agent.nix` | Fixed binary path, added IP resolution, expanded PATH for install script |
| `iac/provision/nix/k8s-worker/modules/base.nix` | Fixed port range syntax |
| `iac/provision/nix/k8s-master/modules/rke2-server.nix` | Added bash to PATH |
| `Makefile` | Added dynamic IP resolution for sync targets |

---

## Next Steps (Phase 3)

1. Install Cilium CNI via Helmfile
2. Verify nodes transition to "Ready" status
3. Deploy CoreDNS and metrics-server
4. Test pod scheduling across workers

---

*Document created: 2026-01-24*
*RKE2 Version: v1.31.4+rke2r1*
*NixOS Version: 26.05 (Yarara)*
