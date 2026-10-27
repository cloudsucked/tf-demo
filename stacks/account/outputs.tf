output "petstore_tunnel_id" {
  description = "Cloudflare Tunnel ID for the Petstore API Shield demo origin."
  value       = cloudflare_zero_trust_tunnel_cloudflared.petstore.id
}

output "petstore_tunnel_token" {
  description = "Token used by cloudflared on the Petstore origin VM."
  value       = data.cloudflare_zero_trust_tunnel_cloudflared_token.petstore.token
  sensitive   = true
}
