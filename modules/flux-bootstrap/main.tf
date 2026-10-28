terraform { required_version = ">= 1.9, < 2.0" }
variable "connection" { type = map(string) }
variable "kubeconfig_path" { type = string }
variable "flux_version" {
  type    = string
  default = "v2.10.0"
}
resource "terraform_data" "flux" {
  input = {
    cluster_id     = var.connection.cluster_id
    private_fqdn   = var.connection.private_fqdn
    kubeconfig     = var.kubeconfig_path
    flux_client_id = var.connection.flux_client_id
    flux_version   = var.flux_version
  }
  triggers_replace = [var.connection.cluster_id, var.flux_version, var.connection.flux_client_id]
  provisioner "local-exec" {
    command = "bash '${path.module}/../../scripts/bootstrap-flux.sh'"
    environment = {
      KUBECONFIG       = self.input.kubeconfig
      LAB_PRIVATE_FQDN = self.input.private_fqdn
      FLUX_VERSION     = self.input.flux_version
      FLUX_CLIENT_ID   = self.input.flux_client_id
    }
  }
  provisioner "local-exec" {
    when    = destroy
    command = "bash '${path.module}/../../scripts/uninstall-flux.sh'"
    environment = {
      KUBECONFIG       = self.input.kubeconfig
      LAB_PRIVATE_FQDN = self.input.private_fqdn
    }
  }
}
