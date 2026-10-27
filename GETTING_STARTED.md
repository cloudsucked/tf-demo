# Getting started

This guide takes a fresh clone to a working Petstore API Shield demo:

```
traffic.py ──► Cloudflare (API Shield, WAF, rate limiting) ──► Tunnel ──► cloudflared ──► Petstore (GCP VM, no public IP)
```

You will create three HCP Terraform workspaces, a few gitignored local files,
and then apply three Terraform stacks in order.

## 1. Prerequisites

**Tools**

- Terraform CLI 1.10 or later
- `gcloud` CLI
- Python 3.11 or later
- `curl`

**Accounts and entitlements**

- **Cloudflare:** an account and a zone on the Enterprise plan with **API Shield**
  (API Security). Rate limiting by JWT claim needs **Advanced Rate Limiting**.
  Sequence mitigation is a closed beta; without it, the sequence rule never matches
  but everything else works.
- **HCP Terraform:** an organization. State is stored there and Terraform runs locally.
- **GCP:** a project with billing enabled. The demo runs one `e2-small` VM plus Cloud NAT.

**Values to collect**

| Value | Where to find it |
| --- | --- |
| Cloudflare account ID | Dashboard > account home > **Account ID** (or `Copy account ID` in the account menu) |
| Cloudflare zone ID | Dashboard > your zone > **Overview** > API section |
| Demo hostname | Any unused name in your zone, for example `petstore.example.com` |
| HCP Terraform organization | https://app.terraform.io > organization name |
| GCP project ID | `gcloud projects list` |

## 2. Cloudflare API token

Create a custom API token (**My Profile > API Tokens > Create Token**) with:

| Scope | Permission |
| --- | --- |
| Account | Cloudflare Tunnel: Edit |
| Zone | Zone: Read |
| Zone | DNS: Edit |
| Zone | Zone WAF: Edit |
| Zone | API Gateway: Edit |
| Account | Magic Firewall: Edit (only with `network_firewall_enabled = true`) |

Limit it to your account and zone. Do not type the token directly on the command
line or in `export TOKEN=...` commands, because it ends up in your shell
history. Use a hidden prompt instead:

```sh
read -rs CLOUDFLARE_API_TOKEN && export CLOUDFLARE_API_TOKEN
```

## 3. HCP Terraform workspaces

Log the Terraform CLI in to HCP Terraform:

```sh
terraform login
```

In your organization, create three **CLI-driven** workspaces (**Workspaces >
New > Workspace > CLI-Driven Workflow**):

| Stack | Suggested workspace name |
| --- | --- |
| `stacks/account` | `orangecloud` (or any name; see `account_workspace` below) |
| `stacks/gcp/petstore-origin` | `gcp-petstore-origin` |
| `stacks/zones/<zone>` | `cf-<account_id>-zone-<zone-name-with-dashes>` |

For each workspace, go to **Settings > General > Execution Mode**, select
**Custom > Local**, and save. With Remote mode, plans run in HCP Terraform
without your local credentials and fail.

The GCP and zone stacks read the account stack's outputs (tunnel token and ID)
through `terraform_remote_state`. In the account workspace, go to **Settings >
General > Remote state sharing** and share it with the other two workspaces.

If you name the account workspace something other than `orangecloud`, set
`account_workspace` in the GCP and zone `terraform.tfvars`.

## 4. Optional: rename the zone stack

The zone stack lives in `stacks/zones/orangecloud.dev`. To name it after your
zone:

```sh
git mv stacks/zones/orangecloud.dev stacks/zones/example.com
```

Then update the `stacks/zones/...` entry in `.github/workflows/terraform.yml`,
and set `ZONE_STACK=stacks/zones/example.com` when you run the demo scripts. The
rest of this guide uses `stacks/zones/<zone>`.

## 5. Local configuration files

Each stack needs two gitignored files, created from the committed examples:

```sh
for d in stacks/account stacks/gcp/petstore-origin stacks/zones/<zone>; do
  cp "$d/backend.hcl.example" "$d/backend.hcl"
  cp "$d/terraform.tfvars.example" "$d/terraform.tfvars"
  chmod 600 "$d/terraform.tfvars"
done
```

### `backend.hcl`

Set `organization` and the workspace `name` from step 3, for example:

```hcl
organization = "my-org"

workspaces {
  name = "gcp-petstore-origin"
}
```

### `terraform.tfvars`

| Stack | Required variables |
| --- | --- |
| `stacks/account` | `cloudflare_api_token`, `cloudflare_account_id`, `petstore_hostname` |
| `stacks/gcp/petstore-origin` | `gcp_project_id`, `hcp_organization` |
| `stacks/zones/<zone>` | `cloudflare_api_token`, `cloudflare_zone_id`, `hcp_organization`, `petstore_hostname`, `petstore_jwt_public_key` |

Use the same `petstore_hostname` in the account and zone stacks. Each example
file lists optional variables and their defaults.

These files are plaintext and hold your API token, so never commit or share
them. `.gitignore` already excludes `*.tfvars`, `backend.hcl`, and the JWT
private key.

### JWT signing key

The traffic generator signs ES256 JWTs, and Cloudflare validates them with the
matching public key:

```sh
cd demo/petstore-api-shield
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python traffic.py keygen
cd ../..
```

`keygen` writes `jwt-private.pem` (gitignored, mode 600) and prints a
`petstore_jwt_public_key = { ... }` block. Paste that block into
`stacks/zones/<zone>/terraform.tfvars`. Run `traffic.py pubkey` to print it again.

### Existing zone rulesets

A zone has at most one entrypoint ruleset per phase. If your zone already has
one for custom rules, rate limiting, or managed rules (for example, created in
the dashboard), Terraform must import it instead of creating a new one. To list
them:

```sh
curl -s "https://api.cloudflare.com/client/v4/zones/<zone_id>/rulesets" \
  --header "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  | python3 -c 'import json, sys
for r in json.load(sys.stdin)["result"]:
    if r["kind"] == "zone" and r["phase"] in ("http_request_firewall_custom", "http_ratelimit", "http_request_firewall_managed"):
        print(r["phase"], r["id"])'
```

Add each result to `stacks/zones/<zone>/terraform.tfvars`:

```hcl
existing_entrypoint_ruleset_ids = {
  http_request_firewall_custom = "<ruleset-id>"
}
```

**Warning:** Terraform then owns these rulesets, so any rules already in them
are replaced by the rules in this repository. Check the plan, and copy rules
you want to keep into the HCL first.

## 6. Initialize and apply

Apply the stacks in this order, and review every plan before you confirm it:

```sh
# 1. Tunnel
terraform -chdir=stacks/account init -backend-config=backend.hcl
terraform -chdir=stacks/account apply

# 2. GCP origin VM
gcloud auth login
gcloud auth application-default login
terraform -chdir=stacks/gcp/petstore-origin init -backend-config=backend.hcl
terraform -chdir=stacks/gcp/petstore-origin apply

# 3. DNS, API Shield, WAF, and rate limiting
terraform -chdir=stacks/zones/<zone> init -backend-config=backend.hcl
terraform -chdir=stacks/zones/<zone> apply
```

The VM needs a minute or two after the apply to pull images and connect the
tunnel. To check:

```sh
curl -s -o /dev/null -w '%{http_code}\n' https://<petstore_hostname>/api/v3/openapi.json   # 200
```

### Activate sequence tracking

The Terraform provider has no resource for API sequence rules, which turn on
sequence tracking. The WAF rule `petstore_order_requires_inventory` does the
enforcement, but its `cf.sequence.*` fields stay empty until at least one
sequence rule exists. This script creates a single log-only rule:

```sh
ZONE_STACK=stacks/zones/<zone> demo/petstore-api-shield/sequence-rules.sh
```

The script replaces all API sequence rules in the zone.

## 7. Generate traffic

```sh
cd demo/petstore-api-shield
export ZONE_STACK=stacks/zones/<zone>   # skip if you kept the default directory
.venv/bin/python traffic.py -v attack all                 # one burst of each attack
.venv/bin/python traffic.py baseline --duration 120       # compliant traffic only
.venv/bin/python traffic.py demo --duration 3600          # baseline with attack bursts every 30s
```

The target URL is read from the zone stack's `petstore_url` output. Override it
with `--base-url` or `PETSTORE_BASE_URL`.

Expected results:

| Scenario | Response |
| --- | --- |
| `baseline` | `200` |
| `jwt`, `schema`, `sequence` | `403` |
| `volumetric` | `429` after about 20 requests in 10 seconds |
| `shadow` | `404` or `405` from the origin (logged, not blocked, so API Discovery can see them) |

To show detections without blocking, set `petstore_mitigation_action = "log"`.

API Discovery needs about 24 hours of traffic, and volumetric abuse
recommendations need about 7 days. Run the `demo` mode regularly before
showing those features. See `demo/petstore-api-shield/README.md` for what each
scenario sends.

## Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| `terraform init` prompts for `organization` | Run `init` with `-backend-config=backend.hcl`. |
| `Unable to find remote state` | The account stack is not applied yet, `hcp_organization` or `account_workspace` is wrong, or the account workspace does not share state with this workspace. |
| A plan runs remotely, or fails with missing credentials | The workspace is set to Remote execution; change it to Local. |
| Apply fails creating a `cloudflare_ruleset` (`already exists`) | Add the existing ruleset ID to `existing_entrypoint_ruleset_ids` (step 5). |
| Rate limit rule rejected | The zone lacks Advanced Rate Limiting, which JWT-claim characteristics need. |
| `traffic.py` reports `ERR:URLError` (`CERTIFICATE_VERIFY_FAILED`) | TLS inspection (for example, Cloudflare Zero Trust) with a root CA that Python does not trust. Add the root to Python's CA bundle or set `SSL_CERT_FILE`. |
| `curl` to the hostname returns `502` or `530` | The tunnel is not connected yet. SSH in with the GCP stack's `ssh_command` output and check `sudo journalctl -u cloudflared -u petstore`. |

## Teardown

Destroy the stacks in reverse order:

```sh
terraform -chdir=stacks/zones/<zone> destroy
terraform -chdir=stacks/gcp/petstore-origin destroy
terraform -chdir=stacks/account destroy
```

Some objects survive `destroy` and must be removed in the dashboard or API:

- the API Shield session identifier
- the tunnel configuration
- the API sequence rule (`DELETE /zones/<zone_id>/api_gateway/seqrules/rules/<id>`)

Destroying the zone stack deletes the entrypoint rulesets it manages, including
any that were imported.
