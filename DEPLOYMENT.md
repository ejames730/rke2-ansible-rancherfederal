# RKE2 Cluster Deployment with rke2-ansible

This guide walks through deploying a production-ready RKE2 Kubernetes cluster using the `rancherfederal/rke2-ansible` playbook. This example deploys a 3-node control plane with 2 worker nodes on Rocky Linux 9.7.

## Prerequisites

### On Your Local Machine (Ansible Controller)
- Ansible installed (`pip install ansible`)
- SSH access to all cluster nodes
- SSH keys configured with proper permissions (600)
- `kubectl` installed (optional, for post-deployment verification)

### On Your Cluster Nodes
- Rocky Linux 9.7 (or compatible RHEL-based OS) freshly installed
- Network connectivity between all nodes
- SSH server running and accessible
- Sudo access (passwordless sudo recommended)

## Initial Setup

### 1. Clone the Repository

```bash
git clone https://github.com/rancherfederal/rke2-ansible.git
cd rke2-ansible
```

### 2. Create Your Inventory Directory

```bash
mkdir -p inventory/my-cluster/group_vars
```

### 3. Configure SSH Access

Update your SSH config file (`~/.ssh/config`) with your node information:

```
Host rke2-cp1
    HostName <control-plane-1-ip>
    User cloud-user
    IdentityFile ~/.ssh/id_proxmox

Host rke2-cp2
    HostName <control-plane-2-ip>
    User cloud-user
    IdentityFile ~/.ssh/id_proxmox

Host rke2-cp3
    HostName <control-plane-3-ip>
    User cloud-user
    IdentityFile ~/.ssh/id_proxmox

Host rke2-wk1
    HostName <worker-1-ip>
    User cloud-user
    IdentityFile ~/.ssh/id_proxmox

Host rke2-wk2
    HostName <worker-2-ip>
    User cloud-user
    IdentityFile ~/.ssh/id_proxmox
```

Ensure your private key has correct permissions:
```bash
chmod 600 ~/.ssh/id_proxmox
```

### 4. Verify SSH Access

Test connectivity to your first control plane node:
```bash
ssh rke2-cp1 "sudo -l"
```

You should see sudo permissions without being prompted for a password.

## Configure Ansible Inventory

### hosts.yml

Create `inventory/my-cluster/hosts.yml` with your actual IP addresses. Replace the IPs with your actual node IPs:

```bash
cat > ~/vscode/rke2-ansible/inventory/my-cluster/hosts.yml << 'EOF'
---
rke2_cluster:
  children:
    rke2_servers:
      hosts:
        rke2-cp1:
          ansible_host: 10.2.1.186
        rke2-cp2:
          ansible_host: 10.2.1.187
        rke2-cp3:
          ansible_host: 10.2.1.188
    rke2_agents:
      hosts:
        rke2-wk1:
          ansible_host: 10.2.1.189
        rke2-wk2:
          ansible_host: 10.2.1.190
EOF
```

### group_vars/all.yml

Create `inventory/my-cluster/group_vars/all.yml` with cluster-wide settings:

```bash
cat > ~/vscode/rke2-ansible/inventory/my-cluster/group_vars/all.yml << 'EOF'
---
ansible_user: cloud-user
ansible_private_key_file: ~/.ssh/id_proxmox
ansible_become: true
ansible_become_method: sudo
cluster_rke2_config:
  selinux: true
EOF
```

**Key variables:**
- `ansible_user`: SSH user for remote nodes
- `ansible_private_key_file`: Path to your SSH private key
- `ansible_become`: Enable privilege escalation (sudo)
- `cluster_rke2_config`: RKE2-specific configuration applied to all nodes
  - `selinux: true`: Enables SELinux support (recommended for Rocky)

### group_vars/rke2_servers.yml

Create `inventory/my-cluster/group_vars/rke2_servers.yml` for control plane settings:

```bash
cat > ~/vscode/rke2-ansible/inventory/my-cluster/group_vars/rke2_servers.yml << 'EOF'
---
rke2_servers:
  vars:
    group_rke2_config: {}
EOF
```

### group_vars/rke2_agents.yml

Create `inventory/my-cluster/group_vars/rke2_agents.yml` for worker settings:

```bash
cat > ~/vscode/rke2-ansible/inventory/my-cluster/group_vars/rke2_agents.yml << 'EOF'
---
rke2_agents:
  vars:
    group_rke2_config: {}
EOF
```

## Deployment

### Verify Inventory

Before deploying, verify your inventory is correct:

```bash
ansible-inventory -i inventory/my-cluster/hosts.yml --list
```

This should show all 5 nodes organized under `rke2_servers` and `rke2_agents`.

### Run the Playbook

Deploy RKE2 to all nodes:

```bash
ansible-playbook site.yml -i inventory/my-cluster/hosts.yml
```

**Expected runtime:** 10-20 minutes depending on network speed and node performance.

The playbook will:
1. Install RKE2 on all control plane nodes (with high availability)
2. Install RKE2 on all worker nodes
3. Configure SELinux support
4. Set up the cluster

### Monitor Progress

Watch for output indicating successful installation on each node. If errors occur, the playbook will stop and display the error message.

## Post-Deployment

### Retrieve kubeconfig

After successful deployment, retrieve the kubeconfig from the first control plane node:

```bash
mkdir -p ~/.kube
scp cloud-user@10.2.1.186:/etc/rancher/rke2/rke2.yaml ~/.kube/config
chmod 600 ~/.kube/config
```

### Update Server Address in kubeconfig

Edit `~/.kube/config` and change the server address from `127.0.0.1` to your control plane IP:

```bash
sed -i 's/127.0.0.1/10.2.1.186/g' ~/.kube/config
```

Or manually edit the file and change:
```yaml
server: https://127.0.0.1:6443
```
to:
```yaml
server: https://10.2.1.186:6443
```

### Verify Cluster

Check that all nodes are ready:

```bash
kubectl get nodes
```

Expected output:
```
NAME      STATUS   ROLES                       AGE   VERSION
rke2-cp1  Ready    control-plane,etcd,master  2m    v1.X.X+rke2rX
rke2-cp2  Ready    control-plane,etcd,master  2m    v1.X.X+rke2rX
rke2-cp3  Ready    control-plane,etcd,master  2m    v1.X.X+rke2rX
rke2-wk1  Ready    <none>                     1m    v1.X.X+rke2rX
rke2-wk2  Ready    <none>                     1m    v1.X.X+rke2rX
```

Check cluster health:

```bash
kubectl get cs
kubectl cluster-info
```

## Troubleshooting

### SSH Connection Issues

If you get "Permission denied" errors:
1. Verify SSH key has correct permissions: `chmod 600 ~/.ssh/id_proxmox`
2. Test SSH manually: `ssh rke2-cp1 "whoami"`
3. Verify the user exists on the node (should be `cloud-user` for cloud images)

### Ansible Connection Issues

If Ansible can't connect:
1. Run with verbose output: `ansible-playbook site.yml -i inventory/my-cluster/hosts.yml -vv`
2. Check your `hosts.yml` has correct IPs for `ansible_host`
3. Verify sudoers configuration: `ssh rke2-cp1 "sudo -l"`

### RKE2 Installation Issues

If RKE2 fails to install:
1. Check that nodes have internet access (required to download RKE2)
2. Verify disk space: `ssh rke2-cp1 "df -h"`
3. Check Rocky Linux version: `ssh rke2-cp1 "cat /etc/os-release"`

### SELinux Issues

If you encounter SELinux denials, you can temporarily disable it for troubleshooting:
```bash
ssh rke2-cp1 "sudo setenforce 0"
```

Then restart RKE2:
```bash
ssh rke2-cp1 "sudo systemctl restart rke2-server"
```

## Advanced Configuration

### Specifying RKE2 Version

To pin a specific RKE2 version, add to `group_vars/all.yml`:

```yaml
all:
  vars:
    rke2_install_version: v1.29.12+rke2r1
```

See [RKE2 releases](https://github.com/rancher/rke2/releases) for available versions.

### Enabling CIS Hardening

To enable CIS security hardening, add to `group_vars/rke2_servers.yml`:

```yaml
rke2_servers:
  vars:
    group_rke2_config:
      profile: cis
```

### Custom CNI

To use Cilium instead of the default Flannel:

```yaml
rke2_servers:
  vars:
    group_rke2_config:
      cni:
        - cilium
      disable-kube-proxy: true
```

## Scaling: Adding More Worker Nodes

To add additional worker nodes to your existing cluster:

### 1. Update SSH Config

Add the new node to your `~/.ssh/config`:

```
Host rke2-wk3
    HostName <worker-3-ip>
    User cloud-user
    IdentityFile ~/.ssh/id_proxmox
```

### 2. Update Ansible Inventory

Edit `inventory/my-cluster/hosts.yml` and add the new worker under `rke2_agents`:

```bash
cat > ~/vscode/rke2-ansible/inventory/my-cluster/hosts.yml << 'EOF'
---
rke2_cluster:
  children:
    rke2_servers:
      hosts:
        rke2-cp1:
          ansible_host: 10.2.1.186
        rke2-cp2:
          ansible_host: 10.2.1.187
        rke2-cp3:
          ansible_host: 10.2.1.188
    rke2_agents:
      hosts:
        rke2-wk1:
          ansible_host: 10.2.1.189
        rke2-wk2:
          ansible_host: 10.2.1.190
        rke2-wk3:
          ansible_host: 10.2.1.191
EOF
```

### 3. Verify SSH Access

Test connectivity to the new node:

```bash
ssh rke2-wk3 "sudo -l"
```

### 4. Run the Playbook

Deploy RKE2 to the new worker:

```bash
cd ~/vscode/rke2-ansible
ansible-playbook site.yml -i inventory/my-cluster/hosts.yml
```

The playbook will detect that control plane nodes are already configured and will only deploy to the new worker node.

### 5. Verify the New Node

Check that the new node joined the cluster:

```bash
kubectl get nodes
```

You should see `rke2-wk3` in the Ready state within a few minutes.

## Additional Resources

- [RKE2 Documentation](https://docs.rke2.io/)
- [rke2-ansible Repository](https://github.com/rancherfederal/rke2-ansible)
- [RKE2 Security Hardening](https://docs.rke2.io/security/hardening_guide)
- [RKE2 SELinux Support](https://docs.rke2.io/security/selinux)

## Replicating This Setup

To replicate this setup in another environment:

1. Update IPs in `inventory/my-cluster/hosts.yml`
2. Update SSH config with new hostnames/IPs
3. Verify SSH access to all nodes
4. Run the playbook: `ansible-playbook site.yml -i inventory/my-cluster/hosts.yml`

All other configuration files can remain the same.
