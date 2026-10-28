resource "kubernetes_manifest" "source" {
  manifest = {
    apiVersion = "source.toolkit.fluxcd.io/v1"
    kind       = "OCIRepository"
    metadata   = { name = "workbook-04", namespace = "flux-system" }
    spec = {
      interval = "30s"
      timeout  = "30s"
      provider = "azure"
      url      = "oci://${var.connection.acr_login_server}/helm/workbook"
      ref      = { tag = "0.1.0" }
    }
  }
}
resource "kubernetes_manifest" "release" {
  manifest = {
    apiVersion = "helm.toolkit.fluxcd.io/v2"
    kind       = "HelmRelease"
    metadata   = { name = "workbook-04", namespace = kubernetes_namespace_v1.lab.metadata[0].name }
    spec = {
      interval    = "30s"
      timeout     = "2m"
      releaseName = "workbook-04"
      chartRef    = { kind = "OCIRepository", name = "workbook-04", namespace = "flux-system" }
    }
  }
  depends_on = [kubernetes_manifest.source]
}
