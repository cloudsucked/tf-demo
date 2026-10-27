# Cloudflare Network Firewall (formerly Magic Firewall) policies are rules in the
# account's root ruleset for the magic_transit phase. Requires Magic Transit or
# Magic WAN, so it is disabled by default.

import {
  for_each = var.network_firewall_enabled && var.existing_network_firewall_ruleset_id != null ? toset([var.existing_network_firewall_ruleset_id]) : toset([])
  to       = cloudflare_ruleset.network_firewall[0]
  id       = "accounts/${local.account_id}/${each.value}"
}

resource "cloudflare_ruleset" "network_firewall" {
  count = var.network_firewall_enabled ? 1 : 0

  account_id = local.account_id
  name       = "Magic Firewall Root Ruleset"
  kind       = "root"
  phase      = "magic_transit"

  rules = [
    {
      # ref kept from the dashboard-created rule so the import does not replace it.
      ref         = "9822570498bb4130ac131a63a44fcf9f"
      description = "Testing MFW"
      action      = "block"
      expression  = "(ip.dst eq 1.2.3.4 and ip.proto in {\"igmp\"} and ip.ttl gt 128)"
      enabled     = true
    },
  ]
}
