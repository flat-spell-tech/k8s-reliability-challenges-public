module "app" {
  source         = "../../../modules/flux-app"
  name           = "workbook-01"
  namespace      = kubernetes_namespace_v1.lab.metadata[0].name
  repository_url = var.repository_url
  git_ref        = var.git_ref
  values         = {}
}
