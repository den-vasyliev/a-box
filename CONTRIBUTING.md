# Contributing to abox

## What this project is

abox is a local Kubernetes AI infrastructure sandbox. It provides a reproducible, single-command environment for running AI agents, MCP servers, and AI-aware API gateway. Contributions should move toward that goal: better defaults, more components, improved observability, easier onboarding.

## What we want

- New AI infrastructure components (observability, tracing, eval tooling, vector stores, model proxies)
- Improvements to the bootstrap flow and release pipeline
- Documentation and example configurations
- Bug fixes for the Flux/OCI release pipeline

## What we don't want (yet)

- Application code or agent implementations — those belong in projects that *use* abox
- Alternative cluster provisioners (minikube, k3d) — KinD is intentional
- Replacing Flux with another GitOps tool

## Getting started

```bash
git clone https://github.com/den-vasyliev/abox
cd abox
make run   # provisions a full local cluster
```

Requirements: Docker, macOS or Linux. `make run` installs OpenTofu and k9s automatically. The bootstrap needs **OpenTofu >= 1.11** (the flux-operator-bootstrap module uses write-only attributes).

## Making changes

### Adding a new component

1. If it has CRDs: add a HelmRelease to `releases/crds/`.
2. If it's an app: add a HelmRelease (and any Gateway/HTTPRoute) to `releases/`.
3. Update `README.md` with what the component does and how to reach it.
4. Run `make push` to publish and verify the cluster reconciles cleanly.

### Changing bootstrap (OpenTofu)

Modify files in `bootstrap/`. Test with `make apply`. Document any new design decisions in `CLAUDE.md` under "Key design decisions".

Flux itself is installed by the upstream
[`controlplaneio-fluxcd/flux-operator-bootstrap/kubernetes`](https://github.com/controlplaneio-fluxcd/terraform-kubernetes-flux-operator-bootstrap)
module. Change the `FluxInstance` in `bootstrap/flux-instance.yaml`, not in Helm values.
Bump `var.bootstrap_revision` to force the bootstrap Job to re-run when no input changed,
and set `debug_on_failure = true` on the module to relay the Job logs into the apply output.

### Changing the release pipeline

The CI workflow is at `.github/workflows/flux-push.yaml`. The RSIP filter (`^\d+\.\d+\.\d+$`) and `make push` version bumping logic must stay in sync.

## Pull request guidelines

- One concern per PR.
- PR description must explain *why*, not just *what*.
- Verify `flux get all` shows all resources as `Ready` before submitting.
- See [REVIEW.md](./REVIEW.md) for how PRs are reviewed.

## Commit style

Conventional commits:

```
feat: add Jaeger tracing HelmRelease
fix: pin agentgateway to v2.2.1 to avoid label validation error
chore: bump kagent to 0.7.24
docs: update README quickstart
```

## License

By contributing you agree your contributions are licensed under Apache 2.0.
