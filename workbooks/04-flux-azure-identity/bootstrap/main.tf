terraform { required_version = ">= 1.9, < 2.0" }
variable "connection" { type = map(string) }
variable "kubeconfig_path" { type = string }
module "flux" {
  source          = "../../../modules/flux-bootstrap"
  connection      = var.connection
  kubeconfig_path = var.kubeconfig_path
}
