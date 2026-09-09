#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG=/tmp/setup.log
exec > >(tee -a "$LOG") 2>&1

log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "=== k8sdiy-env setup start ==="

# Detect the platform once. kind and cloud-provider-kind both publish
# linux/darwin builds for amd64/arm64 under the same naming scheme.
case "$(uname -s)" in
  Linux)  PLATFORM_OS=linux ;;
  Darwin) PLATFORM_OS=darwin ;;
  *)      PLATFORM_OS= ;;
esac
case "$(uname -m)" in
  x86_64|amd64)  PLATFORM_ARCH=amd64 ;;
  arm64|aarch64) PLATFORM_ARCH=arm64 ;;
  *)             PLATFORM_ARCH= ;;
esac
if [[ -z "${PLATFORM_OS}" || -z "${PLATFORM_ARCH}" ]]; then
  log "Unsupported platform $(uname -s)/$(uname -m); binary installs will be skipped"
fi

# Install OpenTofu
log "Installing OpenTofu..."
curl -fsSL https://get.opentofu.org/install-opentofu.sh | sh -s -- --install-method standalone
log "OpenTofu installed"

# Install kind CLI. The cluster itself is created by the tehcyx/kind Terraform
# provider, which embeds kind, but the CLI is needed for node-level work:
# kind get nodes, kind load docker-image, kind export logs.
if [[ -n "${PLATFORM_OS}" && -n "${PLATFORM_ARCH}" ]]; then
  log "Installing kind..."
  KIND_VERSION=v0.33.0
  curl -fsSLo /tmp/kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-${PLATFORM_OS}-${PLATFORM_ARCH}"
  sudo install -m 0755 /tmp/kind /usr/local/bin/kind
  rm -f /tmp/kind
  log "kind installed ($(kind version))"
else
  log "Skipping kind install"
fi

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

# Repair nested-Docker egress before anything tries to pull an image. See
# scripts/fix-egress.sh for why Codespaces needs this.
log "Checking Docker egress..."
bash "${SCRIPT_DIR}/fix-egress.sh"

# Initialize Tofu
log "Running tofu init..."
cd bootstrap
tofu init
log "tofu init done"

log "Running tofu apply..."
tofu apply -auto-approve
log "tofu apply done"

# The bootstrap Job and every Flux-managed image are pulled by kubelet on the
# kind nodes, so confirm the nodes can actually reach a registry.
bash "${SCRIPT_DIR}/fix-egress.sh" verify abox \
  || log "WARNING: nodes cannot reach a registry, Flux will not reconcile"

export KUBECONFIG=~/.kube/config

cd ..

# Install cloud-provider-kind (LoadBalancer support)
if [[ -n "${PLATFORM_OS}" && -n "${PLATFORM_ARCH}" ]]; then
  log "Installing cloud-provider-kind..."
  CPK_VERSION=0.11.1
  CPK_URL="https://github.com/kubernetes-sigs/cloud-provider-kind/releases/download/v${CPK_VERSION}/cloud-provider-kind_${CPK_VERSION}_${PLATFORM_OS}_${PLATFORM_ARCH}.tar.gz"
  curl -fsSL "$CPK_URL" -o /tmp/cloud-provider-kind.tar.gz
  tar -xzf /tmp/cloud-provider-kind.tar.gz -C /tmp cloud-provider-kind
  rm -f /tmp/cloud-provider-kind.tar.gz
  nohup /tmp/cloud-provider-kind > /tmp/cloud-provider-kind.log 2>&1 &
  log "cloud-provider-kind started (pid $!)"
else
  log "Skipping cloud-provider-kind install"
fi

log "=== setup complete ==="
