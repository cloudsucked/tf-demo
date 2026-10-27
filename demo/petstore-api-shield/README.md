# Petstore API Shield demo

Swagger Petstore v3 on GCP, published only through Cloudflare Tunnel at
`https://<petstore_hostname>`, protected by API Shield. For setup, see
[GETTING_STARTED.md](../../GETTING_STARTED.md).

```
traffic.py ──► Cloudflare (API Shield, WAF, rate limiting) ──► Tunnel ──► cloudflared ──► petstore (GCP VM, no public IP)
```

| Feature | Where | Behavior |
| --- | --- | --- |
| Endpoint management | `cloudflare_api_shield_operation` | All 19 operations from the OpenAPI spec are saved. |
| Session identifier | `cloudflare_api_shield` | `Authorization` header. |
| Schema validation | `cloudflare_schema_validation_schemas` + WAF rule | Vendored spec, `servers` rewritten to the demo host; violations use `petstore_mitigation_action`. |
| JWT validation | `cloudflare_token_validation_config` + WAF rule | ES256 tokens required on all saved operations except login, logout, and sign-up. |
| Unidentified endpoints | WAF rule (`cf.api_gateway.fallthrough_detected`) | `log` by default so API Discovery still sees them. |
| Rate limiting | `http_ratelimit` rule | 20 req/10s per JWT `sub` on `GET /pet/*`, 60s block. |
| Sequence mitigation | WAF rule (`cf.sequence.*`) + `sequence-rules.sh` | `POST /store/order` must follow `GET /store/inventory` in the same session; the script adds the log-only API sequence rule that activates sequence tracking. |
| Discovery, volumetric abuse detection | Dashboard | Build up from traffic over 24h+ (volumetric needs ~7 days). |

## Files

- `traffic.py`: traffic generator. `keygen` and `pubkey` manage the ES256 signing
  key (`jwt-private.pem`, gitignored). The target URL comes from `--base-url`,
  then `PETSTORE_BASE_URL`, then the zone stack's `petstore_url` output.
- `sequence-rules.sh`: creates the log-only API sequence rule that activates
  sequence tracking. Reads the zone ID and operation IDs from Terraform outputs
  and needs `CLOUDFLARE_API_TOKEN` in the environment.

Both scripts default to the zone stack in `stacks/zones/orangecloud.dev`; set
`ZONE_STACK` if yours is elsewhere.

## Generate traffic

```sh
.venv/bin/python traffic.py baseline --users 8 --duration 600   # compliant traffic only
.venv/bin/python traffic.py attack schema                       # schema|jwt|shadow|volumetric|sequence|all
.venv/bin/python traffic.py -v demo --duration 900 --attack-every 30
```

Baseline users log in, browse pets, check inventory before ordering, and manage
pets with valid ES256 tokens. Attack bursts:

- `schema`: bad enums, wrong types, missing required fields, malformed JSON, wrong content type.
- `jwt`: missing, expired, forged, wrong `kid`, `alg: none`, and garbage tokens.
- `shadow`: undocumented paths and methods (`/api/v3/admin/users`, `/api/v2/pet/1`, `PATCH /pet/1`).
- `volumetric`: one user scraping `GET /pet/{id}` (expect `429` after 20 requests).
- `sequence`: fresh sessions placing orders without checking inventory.

Each run prints response codes per scenario. Blocked requests return `403`
(`429` for rate limiting); see them in **Security > Analytics** and **Events**,
filtered on your demo hostname. Set `petstore_mitigation_action = "log"`
to show detections without blocking.
