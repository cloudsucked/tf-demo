output "cloudflare_zone_id" {
  description = "Zone managed by this stack (used by demo/petstore-api-shield/sequence-rules.sh)."
  value       = var.cloudflare_zone_id
}

output "petstore_url" {
  description = "Public URL of the Petstore API Shield demo."
  value       = "https://${var.petstore_hostname}${local.petstore_base_path}"
}

output "petstore_operation_ids" {
  description = "Saved operation IDs keyed by \"METHOD /path\" from the OpenAPI schema."
  value       = { for k, op in cloudflare_api_shield_operation.petstore : k => op.operation_id }
}

output "petstore_jwt_config_id" {
  description = "Token validation configuration ID for the Petstore demo JWT."
  value       = local.petstore_jwt_config_id
}
