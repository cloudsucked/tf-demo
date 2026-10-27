resource "cloudflare_ruleset" "managed_waf" {
  zone_id = var.cloudflare_zone_id
  name    = "default"
  kind    = "zone"
  phase   = "http_request_firewall_managed"

  rules = [
    {
      ref         = "cloudflare_managed_ruleset"
      description = "Cloudflare Managed Ruleset"
      action      = "execute"
      expression  = "true"
      enabled     = true
      action_parameters = {
        id = "efb7b8c949ac4650a09736fc376e9aee"
      }
    },
  ]
}
