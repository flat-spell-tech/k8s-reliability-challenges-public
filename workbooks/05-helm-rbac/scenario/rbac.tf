resource "kubernetes_service_account_v1" "tenant" {
  metadata {
    name      = "tenant-deployer"
    namespace = kubernetes_namespace_v1.lab.metadata[0].name
  }
}
resource "kubernetes_role_v1" "tenant" {
  metadata {
    name      = "namespaced-chart-delivery"
    namespace = kubernetes_namespace_v1.lab.metadata[0].name
  }
  rule {
    api_groups = [""]
    resources  = ["secrets", "configmaps", "services", "pods", "events"]
    verbs      = ["get", "list", "watch", "create", "patch", "update", "delete"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets"]
    verbs      = ["get", "list", "watch", "create", "patch", "update", "delete"]
  }
}
resource "kubernetes_role_binding_v1" "tenant" {
  metadata {
    name      = "tenant-delivery"
    namespace = kubernetes_namespace_v1.lab.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.tenant.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.tenant.metadata[0].name
    namespace = kubernetes_namespace_v1.lab.metadata[0].name
  }
}
resource "kubernetes_cluster_role_v1" "platform" {
  count = var.fault_enabled ? 0 : 1
  metadata { name = "workbook-05-fixture" }
  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list"]
  }
}
