# ==========================================
# Bootstrap Flux Operator + FluxInstance
# ==========================================
# The bootstrap module runs a Job in the cluster that installs the
# flux-operator Helm chart, applies the FluxInstance with create-if-missing
# semantics and waits for it to become Ready. Resources adopted by Flux are
# left alone on subsequent applies, so Terraform never fights reconciliation.
module "flux_operator" {
  source  = "controlplaneio-fluxcd/flux-operator-bootstrap/kubernetes"
  version = "0.8.0"

  depends_on = [kind_cluster.this]

  revision = var.bootstrap_revision

  gitops_resources = {
    instance_yaml = file("${path.module}/flux-instance.yaml")
  }
}

# ==========================================
# Bootstrap Flux ResourceSetInputProvider
# ==========================================
# Applied after the module because the ResourceSetInputProvider and ResourceSet
# CRDs ship with the flux-operator chart, which the bootstrap Job installs.
resource "kubectl_manifest" "rsip" {
  depends_on = [module.flux_operator]

  yaml_body = <<-YAML
    apiVersion: fluxcd.controlplane.io/v1
    kind: ResourceSetInputProvider
    metadata:
      name: releases-image
      namespace: flux-system
      annotations:
        fluxcd.controlplane.io/reconcileEvery: 5m
    spec:
      type: OCIArtifactTag
      url: ${var.oci_registry}/releases
      filter:
        includeTag: "^\\d+\\.\\d+\\.\\d+$"
        limit: 1
      defaultValues:
        tag: "${var.releases_version}"
  YAML
}

# ==========================================
# Bootstrap Flux ResourceSet
# ==========================================
resource "kubectl_manifest" "rset" {
  depends_on = [kubectl_manifest.rsip]

  yaml_body = <<-YAML
    apiVersion: fluxcd.controlplane.io/v1
    kind: ResourceSet
    metadata:
      name: releases
      namespace: flux-system
    spec:
      inputsFrom:
      - kind: ResourceSetInputProvider
        name: releases-image
      resources:
      - apiVersion: source.toolkit.fluxcd.io/v1
        kind: OCIRepository
        metadata:
          name: releases
          namespace: flux-system
        spec:
          interval: 2m
          url: ${var.oci_registry}/releases
          ref:
            tag: "<< inputs.tag >>"
      - apiVersion: kustomize.toolkit.fluxcd.io/v1
        kind: Kustomization
        metadata:
          name: releases-crds
          namespace: flux-system
        spec:
          interval: 2m
          sourceRef:
            kind: OCIRepository
            name: releases
          path: ./crds
          prune: true
          wait: true
      - apiVersion: kustomize.toolkit.fluxcd.io/v1
        kind: Kustomization
        metadata:
          name: releases
          namespace: flux-system
        spec:
          interval: 2m
          dependsOn:
            - name: releases-crds
          sourceRef:
            kind: OCIRepository
            name: releases
          path: ./
          prune: true
          wait: true
          retryInterval: 30s
  YAML
}
