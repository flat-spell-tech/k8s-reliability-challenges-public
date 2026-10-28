variable "phase" {
  type    = string
  default = "baseline"
  validation {
    condition     = contains(["baseline", "interrupt", "observe", "recover"], var.phase)
    error_message = "Use baseline, interrupt, observe, or recover."
  }
}
resource "terraform_data" "interruption" {
  count            = var.phase == "interrupt" ? 1 : 0
  triggers_replace = [var.connection.cluster_id]
  provisioner "local-exec" {
    command = "bash '${path.module}/../../../scripts/pending-operation.sh' interrupt"
    environment = {
      KUBECONFIG       = var.kubeconfig_path
      LAB_PRIVATE_FQDN = var.connection.private_fqdn
      WORKBOOK_DIR     = abspath(path.module)
    }
  }
  depends_on = [module.app]
}
resource "terraform_data" "recovery" {
  count            = var.phase == "recover" ? 1 : 0
  triggers_replace = [var.connection.cluster_id]
  provisioner "local-exec" {
    command = "bash '${path.module}/../../../scripts/pending-operation.sh' recover"
    environment = {
      KUBECONFIG       = var.kubeconfig_path
      LAB_PRIVATE_FQDN = var.connection.private_fqdn
      WORKBOOK_DIR     = abspath(path.module)
    }
  }
  depends_on = [module.app]
}
