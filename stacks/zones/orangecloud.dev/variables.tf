variable "cloudflare_api_token" {
  description = "Cloudflare API token supplied via a local ignored terraform.tfvars file."
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone managed by this Terraform stack."
  type        = string

  validation {
    condition     = can(regex("^[[:xdigit:]]{32}$", var.cloudflare_zone_id))
    error_message = "cloudflare_zone_id must be a 32-character hexadecimal ID."
  }
}

variable "hcp_organization" {
  description = "HCP Terraform organization holding the account stack state (tunnel ID)."
  type        = string
}

variable "account_workspace" {
  description = "HCP Terraform workspace of the account stack (read for the tunnel ID)."
  type        = string
  default     = "orangecloud"
}

variable "existing_entrypoint_ruleset_ids" {
  description = "IDs of zone entrypoint rulesets that already exist, keyed by phase (http_request_firewall_custom, http_ratelimit, http_request_firewall_managed). They are imported instead of created."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for phase in keys(var.existing_entrypoint_ruleset_ids) : contains(["http_request_firewall_custom", "http_ratelimit", "http_request_firewall_managed"], phase)])
    error_message = "Keys must be http_request_firewall_custom, http_ratelimit, or http_request_firewall_managed."
  }
}

variable "petstore_hostname" {
  description = "Public hostname of the Petstore API Shield demo (must be in this zone and match the account stack)."
  type        = string
}

variable "petstore_jwt_public_key" {
  description = "ES256 (P-256) public JWK used to validate demo JWTs; generate with demo/petstore-api-shield/traffic.py keygen."
  type = object({
    kid = string
    x   = string
    y   = string
  })
}

variable "petstore_mitigation_action" {
  description = "Action for JWT, schema, and sequence violations on the Petstore API (log or block)."
  type        = string
  default     = "block"

  validation {
    condition     = contains(["log", "block"], var.petstore_mitigation_action)
    error_message = "petstore_mitigation_action must be log or block."
  }
}

variable "petstore_fallthrough_action" {
  description = "Action for requests to unidentified Petstore API endpoints (log keeps them visible to API Discovery)."
  type        = string
  default     = "log"

  validation {
    condition     = contains(["log", "block"], var.petstore_fallthrough_action)
    error_message = "petstore_fallthrough_action must be log or block."
  }
}
