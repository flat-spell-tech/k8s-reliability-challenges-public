module "app" {
  source         = "../../../modules/flux-app"
  name           = "pending-lab"
  namespace      = kubernetes_namespace_v1.lab.metadata[0].name
  repository_url = var.repository_url
  git_ref        = var.git_ref
  values         = {}
  suspend        = var.phase == "interrupt" || var.phase == "recover"
}
