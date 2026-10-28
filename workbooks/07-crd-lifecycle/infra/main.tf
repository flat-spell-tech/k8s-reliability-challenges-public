terraform {
  required_version = ">= 1.9, < 2.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.81" }
  }
}
provider "azurerm" {
  resource_provider_registrations = "none"
  subscription_id                 = var.subscription_id
  features {}
}
variable "subscription_id" { type = string }
variable "ssh_public_key" { type = string }
variable "location" {
  type    = string
  default = "eastus"
}
variable "prefix" {
  type    = string
  default = "fstlab"
}
variable "kubernetes_version" {
  description = "Choose a GA patch available in the region and supported by Flux 2.10.0."
  type        = string
  validation {
    condition     = can(regex("^1\\.(35|36|37)\\.[0-9]+$", var.kubernetes_version)) && try(tonumber(split(".", var.kubernetes_version)[2]) >= (split(".", var.kubernetes_version)[1] == "35" ? 2 : split(".", var.kubernetes_version)[1] == "36" ? 1 : 0), false)
    error_message = "Flux 2.10 needs Kubernetes >=1.35.2, >=1.36.1, or >=1.37.0; select an available GA patch."
  }
}
variable "node_vm_size" {
  type    = string
  default = "Standard_D4s_v5"
}
variable "runner_vm_size" {
  type    = string
  default = "Standard_B2ms"
}
variable "node_count" {
  type    = number
  default = 1
}
variable "hub_cidr" {
  type    = string
  default = "10.80.0.0/16"
}
variable "spoke_cidr" {
  type    = string
  default = "10.81.0.0/16"
}
variable "fault_enabled" {
  type    = bool
  default = false
}
module "lab" {
  source               = "../../../modules/azure-lab"
  challenge            = "07"
  location             = var.location
  prefix               = var.prefix
  ssh_public_key       = var.ssh_public_key
  kubernetes_version   = var.kubernetes_version
  node_vm_size         = var.node_vm_size
  runner_vm_size       = var.runner_vm_size
  node_count           = var.node_count
  hub_cidr             = var.hub_cidr
  spoke_cidr           = var.spoke_cidr
  link_hub_api_dns     = true
  block_git_egress     = false
  create_acr           = false
  include_acr_data_dns = true
  create_flux_identity = false
  grant_flux_acr_pull  = true
}
output "connection" {
  value = merge(module.lab.connection, { workbook = "07-crd-lifecycle" })
}

output "fault_enabled" { value = var.fault_enabled }
