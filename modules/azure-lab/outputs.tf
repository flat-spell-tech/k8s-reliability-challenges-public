output "connection" {
  description = "Nonsecret configuration; contains no kubeconfig or access token."
  value = {
    subscription_id   = data.azurerm_client_config.current.subscription_id
    tenant_id         = data.azurerm_client_config.current.tenant_id
    resource_group    = azurerm_resource_group.lab.name
    cluster_name      = azurerm_kubernetes_cluster.lab.name
    cluster_id        = azurerm_kubernetes_cluster.lab.id
    private_fqdn      = azurerm_kubernetes_cluster.lab.private_fqdn
    runner_name       = azurerm_linux_virtual_machine.runner.name
    runner_private_ip = azurerm_network_interface.runner.private_ip_address
    flux_client_id    = try(azurerm_user_assigned_identity.flux[0].client_id, "")
    acr_name          = try(azurerm_container_registry.lab[0].name, "")
    acr_login_server  = try(azurerm_container_registry.lab[0].login_server, "")
    location          = var.location
  }
}
