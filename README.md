# Cloudflare API Shield demo infrastructure

Terraform project that deploys the Swagger Petstore API on a private GCP VM,
publishes it only through Cloudflare Tunnel, and protects it with Cloudflare
API Shield (schema validation, JWT validation, endpoint management, sequence
mitigation), WAF custom and managed rules, and rate limiting. A traffic
generator produces compliant and malicious API traffic for demos.

**New here? Start with [GETTING_STARTED.md](GETTING_STARTED.md).**

## Layout

- `stacks/account/`: account-scoped Cloudflare resources (the tunnel).
- `stacks/zones/<zone>/`: zone-scoped resources (DNS, API Shield, WAF, rate
  limiting). One root per zone; this repository ships `orangecloud.dev`, which
  you can rename to your zone.
- `stacks/gcp/petstore-origin/`: the GCP origin VM.
- `demo/petstore-api-shield/`: demo runbook, traffic generator, and sequence
  rule script.

Each root has its own state in its own HCP Terraform workspace (Local execution
mode), so changes to one zone cannot affect account-wide resources. No account,
zone, or project IDs are hardcoded; each root reads them from a local, gitignored
`terraform.tfvars` (see the `terraform.tfvars.example` file in each root).

Existing resources should be represented by reviewed HCL and imported before
Terraform is allowed to manage them; do not create replacements for resources
that already exist.

## Change workflow

- Run `terraform fmt -check -recursive` and `terraform validate` in each root
  before review. GitHub Actions runs the same checks; add new roots to the
  workflow matrix.
- Import existing resources in small batches and require import-only plans with
  no unintended creates, updates, replacements, or deletions.
- Review every plan before applying, especially changes to DNS, Access/Zero
  Trust policies, certificates, and data services.

For syntax checks without HCP access, use `terraform init -backend=false`.

## References

- [Cloudflare Terraform provider](https://developers.cloudflare.com/terraform/)
- [Cloudflare API Shield](https://developers.cloudflare.com/api-shield/)
- [Cloudflare `cf-terraforming`](https://github.com/cloudflare/cf-terraforming)
- [Cloudflare API token creation](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/)
