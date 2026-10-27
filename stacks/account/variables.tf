variable "cloudflare_api_token" {
  description = "Cloudflare API token supplied via a local ignored terraform.tfvars file."
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account managed by this Terraform stack."
  type        = string

  validation {
    condition     = can(regex("^[[:xdigit:]]{32}$", var.cloudflare_account_id))
    error_message = "cloudflare_account_id must be a 32-character hexadecimal ID."
  }
}

variable "network_firewall_enabled" {
  description = "Manage the Cloudflare Network Firewall (Magic Firewall) root ruleset. Requires Magic Transit or Magic WAN."
  type        = bool
  default     = false
}

variable "existing_network_firewall_ruleset_id" {
  description = "ID of an existing magic_transit root ruleset to import (for example, one created in the dashboard)."
  type        = string
  default     = null
}

variable "petstore_hostname" {
  description = "Public hostname routed through the Petstore demo tunnel (must match the zone stack)."
  type        = string
}
