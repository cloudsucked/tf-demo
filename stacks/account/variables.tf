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

variable "petstore_hostname" {
  description = "Public hostname routed through the Petstore demo tunnel (must match the zone stack)."
  type        = string
}
