#!/bin/bash
# Script to apply fixes for rke2-ansible playbook
# Run this from the root of the rke2-ansible repository
# These fixes address known issues with the rke2-ansible playbook

set -e

echo "Applying fixes to rke2-ansible..."
echo ""

# Fix 1: other_nodes.yml - reorder tasks and increase timeout
echo "Fix 1: Updating other_nodes.yml (reorder tasks, increase timeout)..."
cat > roles/rke2/tasks/other_nodes.yml << 'EOF'
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
echo "  ✓ Applied other_nodes.yml fix"
echo ""

# Fix 2: save_generated_token.yml - use IP address instead of hostname
echo "Fix 2: Updating save_generated_token.yml (use IP address)..."
python3 << 'PYEOF'
with open('roles/rke2/tasks/save_generated_token.yml', 'r') as f:
    content = f.read()

old_line = 'rke2_kubernetes_api_server_host: "{{ token_source_node }}"'
new_line = 'rke2_kubernetes_api_server_host: "{{ hostvars[token_source_node]["ansible_host"] | default(token_source_node) }}"'

if old_line in content:
    content = content.replace(old_line, new_line)
    with open('roles/rke2/tasks/save_generated_token.yml', 'w') as f:
        f.write(content)
    print("  ✓ Applied save_generated_token.yml fix")
else:
    print("  ⚠ save_generated_token.yml already patched or different format")
PYEOF
echo ""

echo "========================================="
echo "Fixes applied successfully!"
echo "========================================="
echo ""
echo "Summary of changes:"
echo "  1. other_nodes.yml:"
echo "     - Reordered tasks to configure before starting service"
echo "     - Increased API server wait timeout from 300s to 600s"
echo ""
echo "  2. save_generated_token.yml:"
echo "     - Use ansible_host (IP) instead of hostname for server URL"
echo "     - Allows agents to connect by IP address"
echo ""
echo "You can now run the playbook:"
echo "  ANSIBLE_ALLOW_BROKEN_CONDITIONALS=True ansible-playbook site.yml -i inventory/my-cluster/hosts.yml"
echo ""
