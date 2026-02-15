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
rke2_install_version: v1.34.3+rke2r3
cluster_rke2_config: {}
EOF
```

**Key variables:**
- `ansible_user`: SSH user for remote nodes
- `ansible_private_key_file`: Path to your SSH private key
- `ansible_become`: Enable privilege escalation (sudo)
- `rke2_install_version`: Pin a specific RKE2 version to avoid internet timeouts when fetching the latest version
- `cluster_rke2_config`: RKE2-specific configuration applied to all nodes (empty dict for basic setup)

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

Deploy RKE2 to all nodes with the broken conditionals flag to work around a playbook bug:

```bash
cd ~/vscode/rke2-ansible
ANSIBLE_ALLOW_BROKEN_CONDITIONALS=True ansible-playbook site.yml -i inventory/my-cluster/hosts.yml
```

**Expected runtime:** 10-20 minutes depending on network speed and node performance.

The playbook will:
1. Install RKE2 on all control plane nodes (with high availability)
2. Install RKE2 on all worker nodes
3. Configure the cluster with the pinned version

**Note:** We use `ANSIBLE_ALLOW_BROKEN_CONDITIONALS=True` to work around a CIS hardening conditional bug in the rke2-ansible playbook. This allows the playbook to continue despite the broken conditional and doesn't affect basic cluster functionality.

### Monitor Progress

Watch for output indicating successful installation on each node. If errors occur, the playbook will stop and display the error message.

### Configure Worker Nodes with Cluster Token

After the initial playbook run completes, the control planes will be running but the worker nodes will need the cluster token to join. Retrieve the token from the first control plane:

```bash
ssh rke2-cp1 "sudo cat /var/lib/rancher/rke2/server/node-token"
```

Save this token - you'll need it. Now update your `inventory/my-cluster/hosts.yml` to include the server URL and token for the agents:

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
          group_rke2_config:
            server: https://10.2.1.186:6443
            token: <YOUR_TOKEN_HERE>
        rke2-wk2:
          ansible_host: 10.2.1.190
          group_rke2_config:
            server: https://10.2.1.186:6443
            token: <YOUR_TOKEN_HERE>
EOF
```

Replace `<YOUR_TOKEN_HERE>` with the actual token from the previous step.

Now run the playbook again to configure the worker nodes:

```bash
ANSIBLE_ALLOW_BROKEN_CONDITIONALS=True ansible-playbook site.yml -i inventory/my-cluster/hosts.yml
```

This second run will configure the worker nodes with the proper server and token, allowing them to join the cluster.

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

### Known Issues with rke2-ansible

The rke2-ansible playbook has a few issues that can be worked around. If you encounter problems, you can apply the following fixes:

#### Issue 1: CIS Hardening Conditional Error

**Error:** `Conditional result (False) was derived from value of type 'NoneType'`

**Cause:** The CIS hardening task has a broken conditional that fails when `cluster_rke2_config` is an empty dict.

**Fix:** Use the `ANSIBLE_ALLOW_BROKEN_CONDITIONALS=True` flag when running the playbook (which we do in our guide).

#### Issue 2: Other Nodes Connection Timeout

**Error:** `Timeout when waiting for rke2-cp1:6443`

**Cause:** The `other_nodes.yml` task tries to wait for the API server by hostname instead of IP, and the order of tasks causes configuration issues.

**Fix:** Apply this patch to `roles/rke2/tasks/other_nodes.yml`:

```bash
cat > ~/vscode/rke2-ansible/roles/rke2/tasks/other_nodes.yml << 'EOF'
---
- name: Generate config.yml on other nodes
  ansible.builtin.include_tasks: config.yml
- name: Flush_handlers
  ansible.builtin.meta: flush_handlers
- name: Ensure rke2 is running
  ansible.builtin.service:
    state: started
    enabled: true
    name: "{{ service_name }}"
- name: Wait for remote k8s apiserver
  ansible.builtin.wait_for:
    host: "{{ rke2_kubernetes_api_server_host }}"
    port: "6443"
    state: present
    timeout: "600"
  changed_when: false
EOF
```

#### Issue 3: Agent Token Not Configured

**Error:** `Error: --token is required` on worker nodes

**Cause:** The playbook doesn't properly pass server and token to agent nodes.

**Fix:** Explicitly set the server and token in the `hosts.yml` at the agent host level (which we do in our guide).

#### Issue 4: API Server Hostname vs IP Address

**Error:** Agents can't connect to control plane by hostname

**Cause:** The `save_generated_token.yml` task uses the node hostname instead of its IP address.

**Fix:** Apply this patch to `roles/rke2/tasks/save_generated_token.yml`:

```bash
python3 << 'EOF'
with open('roles/rke2/tasks/save_generated_token.yml', 'r') as f:
    content = f.read()
old_line = 'rke2_kubernetes_api_server_host: "{{ token_source_node }}"'
new_line = 'rke2_kubernetes_api_server_host: "{{ hostvars[token_source_node]["ansible_host"] | default(token_source_node) }}"'
if old_line in content:
    content = content.replace(old_line, new_line)
    with open('roles/rke2/tasks/save_generated_token.yml', 'w') as f:
        f.write(content)
    print("Applied fix: use IP address for server URL")
EOF
```

### SSL Handshake Timeout

**Error:** `The handshake operation timed out` when fetching RKE2 version

**Cause:** One or more nodes can't reach update.rke2.io to fetch the latest version.

**Fix:** Pin a specific RKE2 version in `group_vars/all.yml` (which we do in our guide):

```yaml
rke2_install_version: v1.34.3+rke2r3
```

This avoids the internet lookup entirely.

### Version Mismatch Between Nodes

If you get version mismatch errors between control planes and agents, ensure all nodes are using the same pinned version in `group_vars/all.yml`.

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
