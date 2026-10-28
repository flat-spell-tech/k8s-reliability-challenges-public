variable "operator_off" {
  description = "First fault phase: remove only the operator and wait for its pods to disappear."
  type        = bool
  default     = false
}
resource "kubernetes_manifest" "source" {
  manifest = {
    apiVersion = "source.toolkit.fluxcd.io/v1"
    kind       = "GitRepository"
    metadata   = { name = "workbook-09", namespace = "flux-system" }
    spec       = { interval = "30s", url = var.repository_url, ref = { branch = var.git_ref } }
  }
}
resource "kubernetes_manifest" "crd" {
  manifest = {
    apiVersion = "kustomize.toolkit.fluxcd.io/v1"
    kind       = "Kustomization"
    metadata   = { name = "workbook-09-crd", namespace = "flux-system" }
    spec = {
      interval  = "30s"
      path      = "./fixtures/finalizers/crd"
      prune     = true
      wait      = true
      sourceRef = { kind = "GitRepository", name = "workbook-09" }
    }
  }
  depends_on = [kubernetes_manifest.source]
}
resource "kubernetes_manifest" "operator" {
  manifest = {
    apiVersion = "kustomize.toolkit.fluxcd.io/v1"
    kind       = "Kustomization"
    metadata   = { name = "workbook-09-operator", namespace = "flux-system" }
    spec = {
      interval  = "30s"
      path      = var.fault_enabled || var.operator_off ? "./fixtures/empty" : "./fixtures/finalizers/operator"
      prune     = true
      wait      = true
      timeout   = "2m"
      dependsOn = [{ name = "workbook-09-crd" }]
      sourceRef = { kind = "GitRepository", name = "workbook-09" }
    }
  }
  depends_on = [kubernetes_manifest.crd, kubernetes_namespace_v1.lab]
}
resource "kubernetes_manifest" "usage" {
  manifest = {
    apiVersion = "kustomize.toolkit.fluxcd.io/v1"
    kind       = "Kustomization"
    metadata   = { name = "workbook-09-usage", namespace = "flux-system" }
    spec = {
      interval       = "30s"
      path           = var.fault_enabled ? "./fixtures/empty" : "./fixtures/finalizers/instances"
      prune          = true
      deletionPolicy = "WaitForTermination"
      timeout        = "1m"
      dependsOn      = [{ name = "workbook-09-operator" }]
      sourceRef      = { kind = "GitRepository", name = "workbook-09" }
    }
  }
  # Healthy destroy must remove custom resources before their operator and CRD.
  depends_on = [kubernetes_manifest.operator]
}
