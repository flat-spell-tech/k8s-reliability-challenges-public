variable "prefix" {
  type    = string
  default = "fstlab"
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,10}$", var.prefix))
    error_message = "prefix must be 3–11 lowercase letters/digits, starting with a letter."
  }
}
variable "challenge" { type = string }
variable "location" {
  type    = string
  default = "eastus"
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.location))
    error_message = "Use an Azure region code such as eastus, not its display name."
  }
}
variable "ssh_public_key" {
  description = "Public key only. The runner has no public IP or inbound SSH rule. Never put a private key here."
  type        = string
  validation {
    condition     = can(regex("^ssh-(ed25519|rsa) ", var.ssh_public_key))
    error_message = "Supply an SSH public key; private key material is not accepted."
  }
}
variable "kubernetes_version" {
  description = "Optional AKS version available in the selected region. Null uses AKS's regional default."
  type        = string
  default     = null
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
  validation {
    condition     = var.node_count >= 1 && var.node_count <= 3
    error_message = "This workbook allows 1–3 nodes."
  }
}
variable "hub_cidr" {
  type    = string
  default = "10.80.0.0/16"
}
variable "spoke_cidr" {
  type    = string
  default = "10.81.0.0/16"
}
variable "link_hub_api_dns" {
  type    = bool
  default = true
}
variable "block_git_egress" {
  type    = bool
  default = false
}
variable "create_acr" {
  type    = bool
  default = false
}
variable "include_acr_data_dns" {
  type    = bool
  default = true
}
variable "create_flux_identity" {
  type    = bool
  default = false
}
variable "grant_flux_acr_pull" {
  type    = bool
  default = true
}
variable "tags" {
  type    = map(string)
  default = {}
}
