module "app" {
  source         = "../../../modules/flux-app"
  name           = "schema-lab"
  namespace      = kubernetes_namespace_v1.lab.metadata[0].name
  repository_url = var.repository_url
  git_ref        = var.git_ref
  values         = {}
  chart_path     = local.chart_path
  crd_policy     = local.crd_policy
}
