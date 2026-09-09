# CODEBASE.md

Ground truth for the abox repository. Covers architecture, component roles, conventions, and forbidden patterns.

---

## What this repo is

abox is a **local AI infrastructure sandbox**. A single `make run` provisions a KinD cluster and reconciles a full AI stack via Flux GitOps. There is no application code — the repo is entirely Kubernetes manifests, OpenTofu, and shell scripts.

---

## Tech Stack

| Layer | Tech | Version |
|---|---|---|
| Cluster | KinD | latest |
| GitOps operator | Flux CD (Flux Operator + FluxInstance) | 2.x |
| Infrastructure as code | OpenTofu | latest |
| AI gateway | agentgateway | v2.2.3 |
| Agent runtime | kagent | 0.10.1 |
| Gateway API | gateway-api (experimental channel) | v1.6.2 |
| Vector database | qdrant | 1.19.1 |
| LLM observability | Arize Phoenix | 12.0.10 |
| OCI artifact store | GHCR | — |
| CI | GitHub Actions | — |

---

## Architecture

### Bootstrap flow

A single `tofu apply` produces a running cluster:

```
KinD cluster
  → module: flux-operator-bootstrap (bootstrap/, upstream controlplaneio-fluxcd module)
      → in-cluster Job: helm install flux-operator
      → apply FluxInstance (create-if-missing), wait for Ready
  → kubectl_manifest: RSIP          (polls ghcr.io/.../releases for semver tags)
  → kubectl_manifest: ResourceSet   (creates OCIRepository + 2 Kustomizations)
```

Flux is installed by the upstream
[`controlplaneio-fluxcd/flux-operator-bootstrap/kubernetes`](https://github.com/controlplaneio-fluxcd/terraform-kubernetes-flux-operator-bootstrap)
module (v0.8.0). It applies resources with create-if-missing semantics and hands
off to Flux once Flux labels them, so re-applies never fight reconciliation. The
`FluxInstance` manifest lives at `bootstrap/flux-instance.yaml`.

Needs OpenTofu >= 1.11 and helm/kubernetes providers >= 3.0.

The ResourceSet creates two Flux Kustomizations:

1. **`releases-crds`** — `path: ./crds` — installs CRDs, runs with `wait: true`
2. **`releases`** — `path: ./` — installs apps, `dependsOn: releases-crds`

This ordering is non-negotiable. Apps reference CRD types (GatewayClass, HelmRelease) that must exist before reconciliation.

### Gitless GitOps via OCI

There is no Git polling. The cluster reconciles from OCI artifacts:

```
make push → git tag v* → CI: flux push artifact → RSIP detects new tag → ResourceSet reconciles
```

The RSIP filter `^\d+\.\d+\.\d+$` matches only clean semver tags. Pre-release and build metadata tags are ignored.

### Directory layout

```
bootstrap/           OpenTofu: cluster.tf, flux.tf, providers.tf, variables.tf
releases/
  crds/              CRD HelmReleases (must reconcile before releases/)
    gateway-api-crds.yaml
    agentgateway-crds.yaml
    kagent-crds.yaml
    kustomization.yaml
  agentgateway.yaml  agentgateway HelmRelease + Gateway resource
  kagent.yaml        kagent HelmRelease + HTTPRoute + ReferenceGrant
  kustomization.yaml
scripts/
  setup.sh           Called by make run
.github/
  workflows/
    flux-push.yaml   Publishes releases/ as OCI artifact on v* tags
```

### Component roles

| Component | Namespace | What it does |
|---|---|---|
| agentgateway | `agentgateway-system` | Gateway API controller; handles AI/MCP-aware routing |
| Gateway `agentgateway-external` | `agentgateway-system` | Single ingress point, port 80, allows routes from all namespaces |
| kagent | `kagent` | AI agent runtime; exposes MCP server on `:8083`, UI on `:8080` |
| HTTPRoute `kagent` | `kagent` | Routes `/api` → kagent MCP, `/` → kagent UI |
| ReferenceGrant `kagent` | `kagent` | Allows the HTTPRoute to reference the gateway in a different namespace |

---

## Conventions

### Adding a new component

1. **CRDs go in `releases/crds/`** as a HelmRelease. Use `install.crds: CreateReplace`.
2. **Apps go in `releases/`** as a HelmRelease. Add `dependsOn: [name: <crd-release>, namespace: <ns>]`.
3. **Namespaces** — define the Namespace resource in the same file as the HelmRelease (Flux handles ordering within a Kustomization).
4. **Cross-namespace routing** — always add a ReferenceGrant in the app's namespace when an HTTPRoute references the gateway.
5. All HelmReleases live in the component's own namespace, not `flux-system` (exception: OCIRepository sources stay in `flux-system`).

### Versioning

- Versions in HelmReleases must be explicit tags (`ref.tag`), never `latest`.
- When bumping a component version, update all three tag references that appear in a HelmRelease (chart tag, controller image tag, UI image tag if present).

### Releasing

`make push` bumps the patch version and pushes. The RSIP picks up the new tag within 5 minutes (poll interval).

---

## Forbidden Patterns

| Pattern | Why |
|---|---|
| `ref.tag: latest` in any HelmRelease | Non-reproducible; Flux won't detect updates |
| App HelmRelease without `dependsOn` pointing to its CRD release | CRD may not exist when app reconciles |
| HTTPRoute referencing a gateway in another namespace without ReferenceGrant | Route will be rejected by the gateway controller |
| Namespace resource only in `releases/crds/` when the app is in `releases/` | CRD kustomization runs in a separate reconcile; namespace may not exist when app installs |
| Patch version > 9 without bumping minor | RSIP uses lexicographic sort: `0.3.10` < `0.3.9` |
| `kubectl_manifest` replaced with `hashicorp/kubernetes` provider for RSIP/ResourceSet | `hashicorp/kubernetes` validates against CRD schema at plan time, breaking single-pass apply |
| Pushing without verifying `flux get all` shows Ready | Broken releases are published to GHCR and reconciled automatically |

---

## Key Design Decisions

**No github_token in Terraform** — Flux is bootstrapped via Helm charts, not `flux_bootstrap_git`. This avoids the need for a deploy key or PAT in OpenTofu state.

**`gavinbunney/kubectl` provider** — Used for RSIP and ResourceSet manifests because it skips CRD schema validation at plan time. This allows a single `tofu apply` to install Flux and immediately create Flux CRD instances.

**kagent pinned to `0.7.23`** — Newer versions embed `+` build metadata in label values, which Kubernetes rejects as invalid. Do not upgrade without verifying label values are clean semver.

**`gateway-api-crds` as a Helm chart** — Managed via HelmRelease (`ghcr.io/den-vasyliev/gateway-api-crds:1.4.0`), not a raw Kustomization. This gives Flux lifecycle management (install, upgrade, uninstall) over the CRDs.

**Gateway listener allows all namespaces** — `allowedRoutes.namespaces.from: All` on the listener. This is intentional for a local sandbox — every new component can add an HTTPRoute without modifying the Gateway.
