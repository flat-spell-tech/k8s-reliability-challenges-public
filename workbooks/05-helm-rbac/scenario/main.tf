module "app" {
  source          = "../../../modules/flux-app"
  name            = "workbook-05"
  namespace       = kubernetes_namespace_v1.lab.metadata[0].name
  repository_url  = var.repository_url
  git_ref         = var.git_ref
  values          = { clusterRole = { enabled = var.fault_enabled } }
  service_account = kubernetes_service_account_v1.tenant.metadata[0].name
  depends_on      = [kubernetes_role_binding_v1.tenant]
}
