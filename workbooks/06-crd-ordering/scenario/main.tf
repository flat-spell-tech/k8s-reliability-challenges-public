resource "kubernetes_manifest" "source" {
  manifest = {
    apiVersion = "source.toolkit.fluxcd.io/v1"
    kind       = "GitRepository"
    metadata   = { name = "workbook-06", namespace = "flux-system" }
    spec       = { interval = "30s", url = var.repository_url, ref = { branch = var.git_ref } }
  }
}
resource "kubernetes_manifest" "crds" {
  manifest = {
    apiVersion = "kustomize.toolkit.fluxcd.io/v1"
    kind       = "Kustomization"
    metadata   = { name = "workbook-06-crds", namespace = "flux-system" }
    spec = {
      interval  = "30s"
      path      = "./fixtures/crd-order/crds"
      prune     = true
      wait      = true
      suspend   = var.fault_enabled
      timeout   = "1m"
      sourceRef = { kind = "GitRepository", name = "workbook-06" }
    }
  }
  depends_on = [kubernetes_manifest.source]
}
resource "kubernetes_manifest" "instances" {
  manifest = {
    apiVersion = "kustomize.toolkit.fluxcd.io/v1"
    kind       = "Kustomization"
    metadata   = { name = "workbook-06-instances", namespace = "flux-system" }
    spec = merge({
      interval       = "30s"
      path           = "./fixtures/crd-order/instances"
      prune          = true
      deletionPolicy = "WaitForTermination"
      timeout        = "1m"
      sourceRef      = { kind = "GitRepository", name = "workbook-06" }
    }, var.fault_enabled ? {} : { dependsOn = [{ name = "workbook-06-crds" }] })
  }
  depends_on = [kubernetes_manifest.crds, kubernetes_namespace_v1.lab]
}
