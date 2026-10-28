variable "schema_count" {
  type    = number
  default = 30
  validation {
    condition     = var.schema_count >= 1 && var.schema_count <= 100 && floor(var.schema_count) == var.schema_count
    error_message = "Use 1–100 synthetic CRDs."
  }
}
variable "release_count" {
  type    = number
  default = 12
  validation {
    condition     = var.release_count >= 1 && var.release_count <= 30 && floor(var.release_count) == var.release_count
    error_message = "Use 1–30 releases; their replica count is zero."
  }
}
variable "schema_padding_kib" {
  type    = number
  default = 32
  validation {
    condition     = var.schema_padding_kib >= 1 && var.schema_padding_kib <= 64 && floor(var.schema_padding_kib) == var.schema_padding_kib
    error_message = "Use 1–64 KiB per synthetic schema description."
  }
}
resource "kubernetes_manifest" "schema" {
  count = var.schema_count
  manifest = {
    apiVersion = "apiextensions.k8s.io/v1"
    kind       = "CustomResourceDefinition"
    metadata   = { name = "loads${count.index}.pressure.reliability.flatspell.io" }
    spec = {
      group = "pressure.reliability.flatspell.io"
      scope = "Namespaced"
      names = { plural = "loads${count.index}", singular = "load${count.index}", kind = "Load${count.index}" }
      versions = [{
        name = "v1", served = true, storage = true
        schema = {
          openAPIV3Schema = {
            type        = "object"
            description = join("", [for i in range(var.schema_padding_kib) : format("%1024s", "x")])
            properties  = { spec = { type = "object", properties = { value = { type = "string" } } } }
          }
        }
      }]
    }
  }
}
resource "kubernetes_manifest" "source" {
  manifest = {
    apiVersion = "source.toolkit.fluxcd.io/v1"
    kind       = "GitRepository"
    metadata   = { name = "workbook-10", namespace = "flux-system" }
    spec       = { interval = "30s", url = var.repository_url, ref = { branch = var.git_ref } }
  }
}
resource "kubernetes_manifest" "release" {
  count = var.release_count
  manifest = {
    apiVersion = "helm.toolkit.fluxcd.io/v2"
    kind       = "HelmRelease"
    metadata   = { name = "pressure-${count.index}", namespace = kubernetes_namespace_v1.lab.metadata[0].name }
    spec = {
      interval    = "30s"
      timeout     = "1m"
      releaseName = "pressure-${count.index}"
      values      = { replicaCount = 0 }
      chart = { spec = {
        chart     = "./fixtures/charts/workbook", reconcileStrategy = "Revision"
        sourceRef = { kind = "GitRepository", name = "workbook-10", namespace = "flux-system" }
      } }
    }
  }
  depends_on = [kubernetes_manifest.schema, kubernetes_manifest.source]
}
resource "terraform_data" "controller_limit" {
  triggers_replace = [var.fault_enabled, var.connection.cluster_id]
  provisioner "local-exec" {
    command = "bash '${path.module}/../../../scripts/set-controller-limit.sh'"
    environment = {
      KUBECONFIG       = var.kubeconfig_path
      LAB_PRIVATE_FQDN = var.connection.private_fqdn
      MEMORY_LIMIT     = var.fault_enabled ? "32Mi" : "512Mi"
    }
  }
  depends_on = [kubernetes_manifest.release]
}
