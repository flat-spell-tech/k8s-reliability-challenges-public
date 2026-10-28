resource "azurerm_container_registry" "lab" {
  count                         = var.create_acr ? 1 : 0
  name                          = "acr${replace(local.name, "-", "")}"
  location                      = var.location
  resource_group_name           = azurerm_resource_group.lab.name
  sku                           = "Premium"
  admin_enabled                 = false
  role_assignment_mode          = "LegacyRegistryPermissions"
  public_network_access_enabled = false
  network_rule_bypass_option    = "AzureServices"
  tags                          = local.tags
}
resource "azurerm_private_dns_zone" "acr" {
  count               = var.create_acr ? 1 : 0
  name                = "privatelink.azurecr.io"
  resource_group_name = azurerm_resource_group.lab.name
}
resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  for_each              = var.create_acr ? { hub = azurerm_virtual_network.hub.id, spoke = azurerm_virtual_network.spoke.id } : {}
  name                  = "${each.key}-acr"
  resource_group_name   = azurerm_resource_group.lab.name
  private_dns_zone_name = azurerm_private_dns_zone.acr[0].name
  virtual_network_id    = each.value
}
resource "azurerm_private_endpoint" "acr" {
  count               = var.create_acr ? 1 : 0
  name                = "pe-acr-${local.name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  subnet_id           = azurerm_subnet.endpoints.id
  private_service_connection {
    name                           = "registry"
    private_connection_resource_id = azurerm_container_registry.lab[0].id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }
  # Deliberately manage individual records: challenge 03 removes only the data
  # endpoint record while retaining the login endpoint. No zone group races it.
}
resource "azurerm_private_dns_a_record" "acr_login" {
  count               = var.create_acr ? 1 : 0
  name                = azurerm_container_registry.lab[0].name
  zone_name           = azurerm_private_dns_zone.acr[0].name
  resource_group_name = azurerm_resource_group.lab.name
  ttl                 = 30
  records = one([for cfg in azurerm_private_endpoint.acr[0].custom_dns_configs : cfg.ip_addresses
  if cfg.fqdn == azurerm_container_registry.lab[0].login_server])
}
resource "azurerm_private_dns_a_record" "acr_data" {
  count               = var.create_acr && var.include_acr_data_dns ? 1 : 0
  name                = "${azurerm_container_registry.lab[0].name}.${var.location}.data"
  zone_name           = azurerm_private_dns_zone.acr[0].name
  resource_group_name = azurerm_resource_group.lab.name
  ttl                 = 30
  records = one([for cfg in azurerm_private_endpoint.acr[0].custom_dns_configs : cfg.ip_addresses
  if cfg.fqdn == "${azurerm_container_registry.lab[0].name}.${var.location}.data.azurecr.io"])
}
resource "azurerm_role_assignment" "kubelet_pull" {
  skip_service_principal_aad_check = true
  count                            = var.create_acr ? 1 : 0
  scope                            = azurerm_container_registry.lab[0].id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.lab.kubelet_identity[0].object_id
}
resource "azurerm_role_assignment" "runner_push" {
  skip_service_principal_aad_check = true
  count                            = var.create_acr ? 1 : 0
  scope                            = azurerm_container_registry.lab[0].id
  role_definition_name             = "AcrPush"
  principal_id                     = azurerm_linux_virtual_machine.runner.identity[0].principal_id
}
resource "azurerm_user_assigned_identity" "flux" {
  count               = var.create_flux_identity ? 1 : 0
  name                = "id-source-${local.name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}
resource "azurerm_federated_identity_credential" "flux" {
  count                     = var.create_flux_identity ? 1 : 0
  name                      = "source-controller"
  user_assigned_identity_id = azurerm_user_assigned_identity.flux[0].id
  issuer                    = azurerm_kubernetes_cluster.lab.oidc_issuer_url
  subject                   = "system:serviceaccount:flux-system:source-controller"
  audience                  = ["api://AzureADTokenExchange"]
}
resource "azurerm_role_assignment" "flux_pull" {
  skip_service_principal_aad_check = true
  count                            = var.create_flux_identity && var.grant_flux_acr_pull ? 1 : 0
  scope                            = azurerm_container_registry.lab[0].id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_user_assigned_identity.flux[0].principal_id
}
