terraform {
  required_version = ">= 1.9, < 2.0"
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.38" }
  }
}
variable "connection" { type = map(string) }
variable "kubeconfig_path" {
  type    = string
  default = null
}
variable "repository_url" {
  type    = string
  default = "https://github.com/flat-spell-tech/k8s-reliability-challenges-public.git"
}
variable "git_ref" {
  type    = string
  default = "main"
}
variable "fault_enabled" {
  type    = bool
  default = false
}
provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.connection.cluster_name
}
resource "kubernetes_namespace_v1" "lab" {
  metadata {
    name   = "workbook-09"
    labels = { "reliability.flatspell.io/workbook" = "09" }
  }
}
