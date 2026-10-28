module "app" {
  source         = "../../../modules/flux-app"
  name           = "workbook-03"
  namespace      = kubernetes_namespace_v1.lab.metadata[0].name
  repository_url = var.repository_url
  git_ref        = var.git_ref
  values         = { image = "${var.connection.acr_login_server}/lab/hello:v1" }
}
