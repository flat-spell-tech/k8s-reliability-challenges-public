data "azurerm_client_config" "current" {}
resource "random_id" "suffix" { byte_length = 3 }
locals {
  name = "${var.prefix}-${var.challenge}-${random_id.suffix.hex}"
  tags = merge(var.tags, { Purpose = "Disposable reliability workbook", Challenge = var.challenge, ManagedBy = "Terraform" })
}
resource "azurerm_resource_group" "lab" {
  name     = "rg-${local.name}"
  location = var.location
  tags     = local.tags
}
resource "azurerm_virtual_network" "hub" {
  name                = "vnet-hub-${local.name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = [var.hub_cidr]
  tags                = local.tags
}
resource "azurerm_virtual_network" "spoke" {
  name                = "vnet-spoke-${local.name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = [var.spoke_cidr]
  tags                = local.tags
}
resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.hub_cidr, 10, 0)]
}
resource "azurerm_subnet" "runner" {
  name                 = "runner"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.hub_cidr, 8, 1)]
}
resource "azurerm_subnet" "aks" {
  name                 = "aks"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [cidrsubnet(var.spoke_cidr, 6, 0)]
}
resource "azurerm_subnet" "endpoints" {
  name                 = "private-endpoints"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [cidrsubnet(var.spoke_cidr, 8, 8)]
}
resource "azurerm_virtual_network_peering" "hub_spoke" {
  name                      = "hub-to-spoke"
  resource_group_name       = azurerm_resource_group.lab.name
  virtual_network_name      = azurerm_virtual_network.hub.name
  remote_virtual_network_id = azurerm_virtual_network.spoke.id
  allow_forwarded_traffic   = true
}
resource "azurerm_virtual_network_peering" "spoke_hub" {
  name                      = "spoke-to-hub"
  resource_group_name       = azurerm_resource_group.lab.name
  virtual_network_name      = azurerm_virtual_network.spoke.name
  remote_virtual_network_id = azurerm_virtual_network.hub.id
  allow_forwarded_traffic   = true
}
resource "azurerm_public_ip" "firewall" {
  name                = "pip-fw-${local.name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}
resource "azurerm_firewall" "lab" {
  name                = "fw-${local.name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"
  ip_configuration {
    name                 = "public"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }
  tags = local.tags
}
resource "azurerm_firewall_application_rule_collection" "web" {
  name                = "lab-bootstrap-web"
  azure_firewall_name = azurerm_firewall.lab.name
  resource_group_name = azurerm_resource_group.lab.name
  priority            = 200
  action              = "Allow"
  rule {
    name             = "isolated-lab-web-egress"
    source_addresses = [var.hub_cidr, var.spoke_cidr]
    target_fqdns     = ["*"]
    protocol {
      port = 80
      type = "Http"
    }
    protocol {
      port = 443
      type = "Https"
    }
  }
}
resource "azurerm_firewall_application_rule_collection" "git_fault" {
  count               = var.block_git_egress ? 1 : 0
  name                = "challenge-block-git"
  azure_firewall_name = azurerm_firewall.lab.name
  resource_group_name = azurerm_resource_group.lab.name
  priority            = 100
  action              = "Deny"
  rule {
    name             = "block-source-fetch"
    source_addresses = [var.spoke_cidr]
    target_fqdns     = ["github.com", "*.github.com"]
    protocol {
      port = 443
      type = "Https"
    }
  }
}
resource "azurerm_firewall_network_rule_collection" "aks" {
  name                = "aks-bootstrap-transport"
  azure_firewall_name = azurerm_firewall.lab.name
  resource_group_name = azurerm_resource_group.lab.name
  priority            = 200
  action              = "Allow"
  rule {
    name                  = "aks-required-tcp"
    source_addresses      = [var.hub_cidr, var.spoke_cidr]
    destination_addresses = ["*"]
    destination_ports     = ["53", "9000"]
    protocols             = ["TCP"]
  }
  rule {
    name                  = "dns-time-tunnel"
    source_addresses      = [var.hub_cidr, var.spoke_cidr]
    destination_addresses = ["*"]
    destination_ports     = ["53", "123", "1194"]
    protocols             = ["UDP"]
  }
}
resource "azurerm_route_table" "egress" {
  name                = "rt-${local.name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  route {
    name                   = "hub-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.lab.ip_configuration[0].private_ip_address
  }
  tags = local.tags
}
resource "azurerm_subnet_route_table_association" "aks" {
  subnet_id      = azurerm_subnet.aks.id
  route_table_id = azurerm_route_table.egress.id
}
resource "azurerm_subnet_route_table_association" "runner" {
  subnet_id      = azurerm_subnet.runner.id
  route_table_id = azurerm_route_table.egress.id
}
resource "azurerm_private_dns_zone" "api" {
  name                = "privatelink.${var.location}.azmk8s.io"
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}
resource "azurerm_private_dns_zone_virtual_network_link" "spoke_api" {
  name                  = "spoke-api"
  resource_group_name   = azurerm_resource_group.lab.name
  private_dns_zone_name = azurerm_private_dns_zone.api.name
  virtual_network_id    = azurerm_virtual_network.spoke.id
}
resource "azurerm_private_dns_zone_virtual_network_link" "hub_api" {
  count                 = var.link_hub_api_dns ? 1 : 0
  name                  = "hub-api"
  resource_group_name   = azurerm_resource_group.lab.name
  private_dns_zone_name = azurerm_private_dns_zone.api.name
  virtual_network_id    = azurerm_virtual_network.hub.id
}
resource "azurerm_user_assigned_identity" "aks" {
  name                = "id-aks-${local.name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}
resource "azurerm_role_assignment" "api_dns" {
  skip_service_principal_aad_check = true
  scope                            = azurerm_private_dns_zone.api.id
  role_definition_name             = "Private DNS Zone Contributor"
  principal_id                     = azurerm_user_assigned_identity.aks.principal_id
}
resource "azurerm_role_assignment" "aks_network" {
  skip_service_principal_aad_check = true
  scope                            = azurerm_virtual_network.spoke.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_user_assigned_identity.aks.principal_id
}
resource "azurerm_role_assignment" "aks_routes" {
  skip_service_principal_aad_check = true
  scope                            = azurerm_route_table.egress.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_user_assigned_identity.aks.principal_id
}
resource "azurerm_user_assigned_identity" "kubelet" {
  name                = "id-kubelet-${local.name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}
resource "azurerm_role_assignment" "kubelet_operator" {
  skip_service_principal_aad_check = true
  scope                            = azurerm_user_assigned_identity.kubelet.id
  role_definition_name             = "Managed Identity Operator"
  principal_id                     = azurerm_user_assigned_identity.aks.principal_id
}
resource "time_sleep" "identity_roles" {
  create_duration = "60s"
  depends_on      = [azurerm_role_assignment.api_dns, azurerm_role_assignment.aks_network, azurerm_role_assignment.aks_routes, azurerm_role_assignment.kubelet_operator]
}
resource "azurerm_kubernetes_cluster" "lab" {
  name                                = "aks-${local.name}"
  location                            = var.location
  resource_group_name                 = azurerm_resource_group.lab.name
  dns_prefix                          = local.name
  kubernetes_version                  = var.kubernetes_version
  private_cluster_enabled             = true
  private_cluster_public_fqdn_enabled = false
  private_dns_zone_id                 = azurerm_private_dns_zone.api.id
  local_account_disabled              = true
  oidc_issuer_enabled                 = true
  workload_identity_enabled           = true
  role_based_access_control_enabled   = true
  sku_tier                            = "Free"
  default_node_pool {
    name            = "system"
    node_count      = var.node_count
    vm_size         = var.node_vm_size
    vnet_subnet_id  = azurerm_subnet.aks.id
    os_disk_size_gb = 64
    os_sku          = "Ubuntu"
    max_pods        = 30
  }
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }
  kubelet_identity {
    client_id                 = azurerm_user_assigned_identity.kubelet.client_id
    object_id                 = azurerm_user_assigned_identity.kubelet.principal_id
    user_assigned_identity_id = azurerm_user_assigned_identity.kubelet.id
  }
  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = data.azurerm_client_config.current.tenant_id
  }
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    service_cidr        = "10.240.0.0/16"
    dns_service_ip      = "10.240.0.10"
    pod_cidr            = "10.244.0.0/16"
    outbound_type       = "userDefinedRouting"
    load_balancer_sku   = "standard"
  }
  tags = local.tags
  depends_on = [time_sleep.identity_roles, azurerm_subnet_route_table_association.aks,
    azurerm_virtual_network_peering.hub_spoke, azurerm_virtual_network_peering.spoke_hub,
    azurerm_firewall_application_rule_collection.web, azurerm_firewall_network_rule_collection.aks,
  azurerm_private_dns_zone_virtual_network_link.spoke_api]
}
resource "azurerm_network_interface" "runner" {
  name                = "nic-runner-${local.name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  ip_configuration {
    name                          = "private"
    subnet_id                     = azurerm_subnet.runner.id
    private_ip_address_allocation = "Dynamic"
  }
  tags = local.tags
}
resource "azurerm_network_security_group" "runner" {
  name                = "nsg-runner-${local.name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  security_rule {
    name                       = "no-inbound-management"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  tags = local.tags
}
resource "azurerm_network_interface_security_group_association" "runner" {
  network_interface_id      = azurerm_network_interface.runner.id
  network_security_group_id = azurerm_network_security_group.runner.id
}
resource "azurerm_linux_virtual_machine" "runner" {
  name                            = "vm-runner-${local.name}"
  location                        = var.location
  resource_group_name             = azurerm_resource_group.lab.name
  size                            = var.runner_vm_size
  admin_username                  = "labadmin"
  network_interface_ids           = [azurerm_network_interface.runner.id]
  disable_password_authentication = true
  admin_ssh_key {
    username   = "labadmin"
    public_key = var.ssh_public_key
  }
  identity { type = "SystemAssigned" }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
  custom_data = base64encode(file("${path.module}/cloud-init.yaml"))
  tags        = local.tags
  depends_on  = [azurerm_subnet_route_table_association.runner, azurerm_firewall_application_rule_collection.web]
}
resource "azurerm_role_assignment" "runner_reader" {
  skip_service_principal_aad_check = true
  scope                            = azurerm_resource_group.lab.id
  role_definition_name             = "Reader"
  principal_id                     = azurerm_linux_virtual_machine.runner.identity[0].principal_id
}
resource "azurerm_role_assignment" "runner_credentials" {
  skip_service_principal_aad_check = true
  scope                            = azurerm_kubernetes_cluster.lab.id
  role_definition_name             = "Azure Kubernetes Service Cluster User Role"
  principal_id                     = azurerm_linux_virtual_machine.runner.identity[0].principal_id
}
resource "azurerm_role_assignment" "runner_kubernetes" {
  skip_service_principal_aad_check = true
  scope                            = azurerm_kubernetes_cluster.lab.id
  role_definition_name             = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id                     = azurerm_linux_virtual_machine.runner.identity[0].principal_id
}
