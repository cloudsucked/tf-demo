# Zone stack

Terraform root for one Cloudflare zone, set by `cloudflare_zone_id`. It manages
the Petstore API Shield demo (`petstore.tf`):

- the proxied CNAME to the tunnel created by the account stack
- saved operations and the uploaded OpenAPI schema (vendored in `schemas/`,
  Petstore v3 1.0.28)
- the API Shield session identifier and JWT validation configuration
- the zone entrypoint rulesets for custom firewall rules, rate limiting, and
  the Cloudflare Managed Ruleset (`waf_managed.tf`)

Entrypoint rulesets that already exist in the zone are imported through
`existing_entrypoint_ruleset_ids` (`imports.tf`). The tunnel ID is read from the
account stack's HCP Terraform workspace (`account_workspace`).

Copy `backend.hcl.example` to `backend.hcl` and `terraform.tfvars.example` to
`terraform.tfvars` (both gitignored). See `GETTING_STARTED.md` at the repository
root.
