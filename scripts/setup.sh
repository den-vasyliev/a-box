#!/bin/bash
set -euo pipefail

LOG=/tmp/setup.log
exec > >(tee -a "$LOG") 2>&1

log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "=== k8sdiy-env setup start ==="

# Install OpenTofu
log "Installing OpenTofu..."
curl -fsSL https://get.opentofu.org/install-opentofu.sh | sh -s -- --install-method standalone
log "OpenTofu installed"

# Install K9s
log "Installing K9s..."
curl -sS https://webi.sh/k9s | sh
log "K9s installed"

# Add aliases to bashrc
cat >> ~/.bashrc <<'EOF'

# k8sdiy-env aliases
alias kk="EDITOR='code --wait' k9s"
alias tf=tofu
alias k=kubectl
EOF

# Initialize Tofu
log "Running tofu init..."
cd bootstrap
tofu init
log "tofu init done"

log "Running tofu apply..."
tofu apply -auto-approve
log "tofu apply done"

export KUBECONFIG=~/.kube/config

cd ..

# Install cloud-provider-kind (LoadBalancer support)
log "Installing cloud-provider-kind..."
ARCH=$(dpkg --print-architecture)
wget -q "https://github.com/kubernetes-sigs/cloud-provider-kind/releases/download/v0.11.1/cloud-provider-kind_0.11.1_linux_${ARCH}.tar.gz" \
  -O /tmp/cloud-provider-kind.tar.gz
tar -xzf /tmp/cloud-provider-kind.tar.gz -C /tmp cloud-provider-kind
rm /tmp/cloud-provider-kind.tar.gz
nohup /tmp/cloud-provider-kind > /tmp/cloud-provider-kind.log 2>&1 &
log "cloud-provider-kind started (pid $!)"


log "=== setup complete ==="
