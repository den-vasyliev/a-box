#!/bin/bash
# Repair nested-Docker egress on hosts that ship both iptables backends.
#
# Docker sets the FORWARD policy to DROP and then whitelists its own bridges.
# On GitHub Codespaces the legacy tables still carry rules written by an older
# Docker that only knew about docker0, while the Docker actually running manages
# the nft backend. The kernel enforces the stale legacy DROP, so docker0 keeps
# working (it is explicitly whitelisted) and every user-defined bridge silently
# loses egress -- including the "kind" network the cluster runs on.
#
# The symptom is a blackhole, not a refusal: image pulls fail with
# "dial tcp: lookup ghcr.io ... i/o timeout" and raw TCP probes hang.
#
# Safe to run anywhere: it no-ops off Linux, without iptables-legacy, or when
# the policy is already permissive.
#
# Usage:
#   scripts/fix-egress.sh              # apply the fix
#   scripts/fix-egress.sh verify NAME  # probe egress from each node of cluster NAME
set -uo pipefail

log() { echo "[$(date '+%H:%M:%S')] fix-egress: $*"; }

apply_fix() {
  if [ "$(uname -s)" != "Linux" ]; then
    log "not Linux, nothing to do"
    return 0
  fi

  if ! command -v iptables-legacy >/dev/null 2>&1; then
    log "no iptables-legacy backend present, nothing to do"
    return 0
  fi

  if ! sudo -n true 2>/dev/null; then
    log "WARNING: passwordless sudo unavailable, skipping firewall check"
    return 0
  fi

  if sudo -n iptables-legacy -S FORWARD 2>/dev/null | grep -q '^-P FORWARD DROP'; then
    log "legacy FORWARD policy is DROP, which blackholes user-defined Docker bridges"
    sudo -n iptables-legacy -P FORWARD ACCEPT
    log "legacy FORWARD policy set to ACCEPT"
  else
    log "legacy FORWARD policy already permissive"
  fi
}

# verify_cluster probes raw TCP egress from every node of a kind cluster. It
# deliberately avoids DNS so a failure means routing, not resolution.
verify_cluster() {
  local cluster="$1" nodes node failed=0

  nodes=$(docker ps --filter "label=io.x-k8s.kind.cluster=${cluster}" --format '{{.Names}}' 2>/dev/null)
  if [ -z "${nodes}" ]; then
    log "no running nodes for cluster '${cluster}', skipping verification"
    return 0
  fi

  for node in ${nodes}; do
    if timeout 5 docker exec "${node}" bash -c '(exec 3<>/dev/tcp/1.1.1.1/53)' 2>/dev/null; then
      log "${node}: egress OK"
    else
      log "${node}: NO EGRESS -- image pulls will fail"
      failed=1
    fi
  done

  if [ "${failed}" -eq 1 ]; then
    log "egress is still blocked after the firewall fix; check for a proxy or"
    log "VNet policy above Docker before running 'make apply'"
    return 1
  fi
}

case "${1:-apply}" in
  verify) verify_cluster "${2:-abox}" ;;
  *)      apply_fix ;;
esac
