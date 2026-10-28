mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = { "subscription_id" : "00000000-0000-0000-0000-000000000001", "tenant_id" : "00000000-0000-0000-0000-000000000008", "object_id" : "00000000-0000-0000-0000-000000000009" }
  }
  mock_resource "azurerm_resource_group" {
    defaults = { "id" : "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/lab-test" }
  }
  mock_resource "azurerm_virtual_network" {
    defaults = { "id" : "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/lab-test/providers/Microsoft.Network/virtualNetworks/test" }
  }
  mock_resource "azurerm_subnet" {
    defaults = { "id" : "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/lab-test/providers/Microsoft.Network/virtualNetworks/test/subnets/test" }
  }
  mock_resource "azurerm_public_ip" {
    defaults = { "id" : "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/lab-test/providers/Microsoft.Network/publicIPAddresses/test" }
  }
  mock_resource "azurerm_route_table" {
    defaults = { "id" : "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/lab-test/providers/Microsoft.Network/routeTables/test" }
  }
  mock_resource "azurerm_network_security_group" {
    defaults = { "id" : "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/lab-test/providers/Microsoft.Network/networkSecurityGroups/test" }
  }
  mock_resource "azurerm_network_interface" {
    defaults = { "id" : "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/lab-test/providers/Microsoft.Network/networkInterfaces/test", "private_ip_address" : "10.80.1.4" }
  }
  mock_resource "azurerm_user_assigned_identity" {
    defaults = { "id" : "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/lab-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/test", "principal_id" : "00000000-0000-0000-0000-000000000003", "client_id" : "00000000-0000-0000-0000-000000000004" }
  }
  mock_resource "azurerm_private_dns_zone" {
    defaults = { "id" : "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/lab-test/providers/Microsoft.Network/privateDnsZones/privatelink.eastus.azmk8s.io" }
  }
  mock_resource "azurerm_container_registry" {
    defaults = { "id" : "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/lab-test/providers/Microsoft.ContainerRegistry/registries/acrfstlab03abc123", "login_server" : "acrfstlab03abc123.azurecr.io" }
  }
  mock_resource "azurerm_kubernetes_cluster" {
    defaults = { "id" : "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/lab-test/providers/Microsoft.ContainerService/managedClusters/test", "private_fqdn" : "test.privatelink.eastus.azmk8s.io", "oidc_issuer_url" : "https://eastus.oic.prod-aks.azure.com/tenant/issuer/", "kubelet_identity" : { "object_id" : "00000000-0000-0000-0000-000000000005", "client_id" : "00000000-0000-0000-0000-000000000006", "user_assigned_identity_id" : "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/lab-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/kubelet" } }
  }
  mock_resource "azurerm_linux_virtual_machine" {
    defaults = { "id" : "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/lab-test/providers/Microsoft.Compute/virtualMachines/runner", "identity" : { "type" : "SystemAssigned", "principal_id" : "00000000-0000-0000-0000-000000000007", "tenant_id" : "00000000-0000-0000-0000-000000000008", "identity_ids" : [] } }
  }
  mock_resource "azurerm_firewall" {
    defaults = { "id" : "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/lab-test/providers/Microsoft.Network/azureFirewalls/test", "ip_configuration" : { "name" : "public", "private_ip_address" : "10.80.0.4", "subnet_id" : "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/lab-test/providers/Microsoft.Network/virtualNetworks/test/subnets/AzureFirewallSubnet", "public_ip_address_id" : "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/lab-test/providers/Microsoft.Network/publicIPAddresses/test" } }
  }
  mock_resource "azurerm_private_endpoint" {
    defaults = { "id" : "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/lab-test/providers/Microsoft.Network/privateEndpoints/test", "custom_dns_configs" : [{ "fqdn" : "acrfstlab03abc123.azurecr.io", "ip_addresses" : ["10.81.8.4"] }, { "fqdn" : "acrfstlab03abc123.eastus.data.azurecr.io", "ip_addresses" : ["10.81.8.5"] }] }
  }
}
mock_provider "random" {
  mock_resource "random_id" {
    defaults = { hex = "abc123" }
  }
}
mock_provider "time" {}
variables {
  challenge      = "03"
  ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEmu14sKjeMBVrX26PGc2bj0NM48KVNNwO28aPnaF9X/ agent@bed07f564247"
}

run "private_baseline" {
  command = apply
  assert {
    condition     = azurerm_kubernetes_cluster.lab.private_cluster_enabled && azurerm_kubernetes_cluster.lab.local_account_disabled && !azurerm_kubernetes_cluster.lab.private_cluster_public_fqdn_enabled
    error_message = "The cluster must remain private and Entra-authenticated."
  }
  assert {
    condition     = length(azurerm_private_dns_zone_virtual_network_link.hub_api) == 1 && azurerm_network_security_group.runner.security_rule != null
    error_message = "The baseline needs a hub DNS link and a private runner security group."
  }
}
run "hub_dns_fault" {
  command = plan
  variables { link_hub_api_dns = false }
  assert {
    condition     = length(azurerm_private_dns_zone_virtual_network_link.hub_api) == 0 && azurerm_private_dns_zone_virtual_network_link.spoke_api.virtual_network_id != null
    error_message = "Only the hub DNS link should disappear."
  }
}
run "egress_fault" {
  command = plan
  variables { block_git_egress = true }
  assert {
    condition     = azurerm_firewall_application_rule_collection.git_fault[0].action == "Deny" && azurerm_firewall_application_rule_collection.git_fault[0].priority < azurerm_firewall_application_rule_collection.web.priority
    error_message = "The specific source deny must precede the lab baseline allow rule."
  }
}
run "acr_data_dns_fault" {
  command = apply
  variables {
    create_acr           = true
    include_acr_data_dns = false
  }
  assert {
    condition     = length(azurerm_private_dns_a_record.acr_login) == 1 && length(azurerm_private_dns_a_record.acr_data) == 0 && !azurerm_container_registry.lab[0].public_network_access_enabled
    error_message = "The login record stays; data DNS fails without a public fallback."
  }
}
run "flux_identity_fault" {
  command = apply
  variables {
    create_acr           = true
    create_flux_identity = true
    grant_flux_acr_pull  = false
  }
  assert {
    condition     = length(azurerm_role_assignment.flux_pull) == 0 && length(azurerm_role_assignment.kubelet_pull) == 1 && azurerm_federated_identity_credential.flux[0].subject == "system:serviceaccount:flux-system:source-controller"
    error_message = "Remove only Flux data-plane access, retaining the kubelet and federated trust."
  }
}
run "identity_repair" {
  command = apply
  variables {
    create_acr           = true
    create_flux_identity = true
    grant_flux_acr_pull  = true
  }
  assert {
    condition     = length(azurerm_role_assignment.flux_pull) == 1 && azurerm_role_assignment.flux_pull[0].scope == azurerm_container_registry.lab[0].id
    error_message = "The repair is registry-scoped AcrPull, not a subscription-wide grant."
  }
}
override_resource {
  target = azurerm_subnet.firewall
  values = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/lab-test/providers/Microsoft.Network/virtualNetworks/test/subnets/AzureFirewallSubnet" }
}
override_resource {
  target = azurerm_kubernetes_cluster.lab
  values = {
    id              = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/lab-test/providers/Microsoft.ContainerService/managedClusters/test"
    private_fqdn    = "test.privatelink.eastus.azmk8s.io"
    oidc_issuer_url = "https://eastus.oic.prod-aks.azure.com/tenant/issuer/"
    kubelet_identity = [{
      object_id                 = "00000000-0000-0000-0000-000000000005"
      client_id                 = "00000000-0000-0000-0000-000000000006"
      user_assigned_identity_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/lab-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/kubelet"
    }]
  }
}
