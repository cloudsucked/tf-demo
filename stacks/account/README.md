# Account stack

Terraform root for account-scoped Cloudflare resources, set by
`cloudflare_account_id`. It manages the Cloudflare Tunnel for the Petstore API
Shield demo. Its outputs (tunnel ID and token) are read through remote state by
`stacks/gcp/petstore-origin/` and the zone stack.

Copy `backend.hcl.example` to `backend.hcl` and `terraform.tfvars.example` to
`terraform.tfvars` (both gitignored), then run
`terraform init -backend-config=backend.hcl`. Keep zone-scoped resources in
`stacks/zones/<zone>/`. See `GETTING_STARTED.md` at the repository root.
