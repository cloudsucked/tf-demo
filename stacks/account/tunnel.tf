resource "cloudflare_zero_trust_tunnel_cloudflared" "petstore" {
  account_id = local.account_id
  name       = "petstore-api-shield-demo"
  config_src = "cloudflare"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "petstore" {
  account_id = local.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.petstore.id

  config = {
    ingress = [
      {
        hostname = var.petstore_hostname
        service  = "http://petstore:8080"
      },
      {
        service = "http_status:404"
      },
    ]
  }
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "petstore" {
  account_id = local.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.petstore.id
}
