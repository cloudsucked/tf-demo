# A zone has at most one entrypoint ruleset per phase. If one already exists
# (for example, created in the dashboard), list its ID in
# existing_entrypoint_ruleset_ids so it is imported instead of failing to create.

import {
  for_each = { for phase, id in var.existing_entrypoint_ruleset_ids : phase => id if phase == "http_request_firewall_custom" }
  to       = cloudflare_ruleset.custom_firewall
  id       = "zones/${var.cloudflare_zone_id}/${each.value}"
}

import {
  for_each = { for phase, id in var.existing_entrypoint_ruleset_ids : phase => id if phase == "http_ratelimit" }
  to       = cloudflare_ruleset.rate_limit
  id       = "zones/${var.cloudflare_zone_id}/${each.value}"
}

import {
  for_each = { for phase, id in var.existing_entrypoint_ruleset_ids : phase => id if phase == "http_request_firewall_managed" }
  to       = cloudflare_ruleset.managed_waf
  id       = "zones/${var.cloudflare_zone_id}/${each.value}"
}
