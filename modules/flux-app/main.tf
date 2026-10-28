terraform {
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.38" }
  }
}
variable "name" { type = string }
variable "namespace" { type = string }
variable "repository_url" { type = string }
variable "git_ref" { type = string }
variable "chart_path" {
  type    = string
  default = "./fixtures/charts/workbook"
}
variable "values" {
  type    = any
  default = {}
}
variable "service_account" {
  type    = string
  default = ""
}
variable "suspend" {
  type    = bool
  default = false
}
variable "crd_policy" {
  type    = string
  default = "Skip"
}
resource "kubernetes_manifest" "source" {
  manifest = {
    apiVersion = "source.toolkit.fluxcd.io/v1"
    kind       = "GitRepository"
    metadata   = { name = var.name, namespace = "flux-system" }
    spec = {
      interval = "30s"
      timeout  = "30s"
      url      = var.repository_url
      ref      = { branch = var.git_ref }
    }
  }
}
resource "kubernetes_manifest" "release" {
  manifest = {
    apiVersion = "helm.toolkit.fluxcd.io/v2"
    kind       = "HelmRelease"
    metadata   = { name = var.name, namespace = var.namespace }
    spec = merge({
      interval    = "30s"
      timeout     = "2m"
      suspend     = var.suspend
      releaseName = var.name
      chart = {
        spec = {
          chart             = var.chart_path
          reconcileStrategy = "Revision"
          sourceRef         = { kind = "GitRepository", name = var.name, namespace = "flux-system" }
        }
      }
      install = { crds = var.crd_policy, remediation = { retries = 0 } }
      upgrade = { crds = var.crd_policy, remediation = { retries = 0 } }
      values  = var.values
    }, var.service_account != "" ? { serviceAccountName = var.service_account } : {})
  }
  depends_on = [kubernetes_manifest.source]
}
