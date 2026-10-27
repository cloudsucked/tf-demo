#!/usr/bin/env bash
# Create the log-only API sequence rule that activates API Shield sequence
# tracking. Enforcement is the WAF custom rule `petstore_order_requires_inventory`
# in the zone stack's petstore.tf; the Cloudflare Terraform provider has no
# sequence rule resource. PUT replaces all sequence rules on the zone.
#
# Reads the zone ID and operation IDs from the zone stack's Terraform outputs.
# Set ZONE_STACK if your zone stack is not stacks/zones/orangecloud.dev.
set -euo pipefail

: "${CLOUDFLARE_API_TOKEN:?set CLOUDFLARE_API_TOKEN to a token with Zone > API Gateway: Edit}"
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
zone_dir="$repo_root/${ZONE_STACK:-stacks/zones/orangecloud.dev}"

zone_id="$(terraform -chdir="$zone_dir" output -raw cloudflare_zone_id)"
ops="$(terraform -chdir="$zone_dir" output -json petstore_operation_ids)"
op() { python3 -c 'import json, sys; print(json.loads(sys.argv[2])[sys.argv[1]])' "$1" "$ops"; }

curl -sS --fail-with-body --request PUT \
  "https://api.cloudflare.com/client/v4/zones/$zone_id/api_gateway/seqrules" \
  --header "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  --json "$(
    cat <<EOF
{
  "rules": [
    {
      "title": "Petstore: sequence tracking (log only)",
      "kind": "allow",
      "action": "log",
      "sequence": ["$(op 'GET /store/inventory')", "$(op 'POST /store/order')"]
    }
  ]
}
EOF
  )"
echo
