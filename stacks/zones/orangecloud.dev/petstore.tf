data "terraform_remote_state" "account" {
  backend = "remote"

  config = {
    organization = var.hcp_organization
    workspaces = {
      name = var.account_workspace
    }
  }
}

locals {
  petstore_base_path = "/api/v3"
  petstore_spec      = yamldecode(file("${path.module}/schemas/petstore-openapi.yaml"))

  # Saved operations use {varN} path templates; each Petstore path has at most one parameter.
  petstore_operations = merge([
    for path, item in local.petstore_spec.paths : {
      for method, _ in item : "${upper(method)} ${path}" => {
        method   = upper(method)
        endpoint = "${local.petstore_base_path}${replace(path, "/\\{[^}]+\\}/", "{var1}")}"
      } if contains(["get", "put", "post", "delete", "patch"], method)
    }
  ]...)

  # Operations that issue or do not need a JWT.
  petstore_jwt_exempt_operations = ["GET /user/login", "GET /user/logout", "POST /user"]

  petstore_jwt_config_id = cloudflare_token_validation_config.petstore.id
  petstore_jwt_sub       = "lookup_json_string(http.request.jwt.claims[\"${local.petstore_jwt_config_id}\"][0], \"sub\")"
}

resource "cloudflare_dns_record" "petstore" {
  zone_id = var.cloudflare_zone_id
  name    = var.petstore_hostname
  type    = "CNAME"
  content = "${data.terraform_remote_state.account.outputs.petstore_tunnel_id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
  comment = "Petstore API Shield demo origin (Cloudflare Tunnel to GCP)"
}

resource "cloudflare_api_shield" "session_identifier" {
  zone_id = var.cloudflare_zone_id

  auth_id_characteristics = [
    {
      name = "authorization"
      type = "header"
    },
  ]
}

resource "cloudflare_api_shield_operation" "petstore" {
  for_each = local.petstore_operations

  zone_id  = var.cloudflare_zone_id
  host     = var.petstore_hostname
  method   = each.value.method
  endpoint = each.value.endpoint
}

resource "cloudflare_schema_validation_schemas" "petstore" {
  zone_id            = var.cloudflare_zone_id
  name               = "petstore-v3"
  kind               = "openapi_v3"
  validation_enabled = true
  source = jsonencode(merge(local.petstore_spec, {
    servers = [{ url = "https://${var.petstore_hostname}${local.petstore_base_path}" }]
  }))

  # Schema operations must be saved before the schema is activated.
  depends_on = [cloudflare_api_shield_operation.petstore]
}

resource "cloudflare_token_validation_config" "petstore" {
  zone_id       = var.cloudflare_zone_id
  token_type    = "JWT"
  title         = "Petstore demo JWT"
  description   = "ES256 tokens signed by the Petstore demo traffic generator."
  token_sources = ["http.request.headers[\"authorization\"][0]"]

  credentials = {
    keys = [
      {
        kty = "EC"
        alg = "ES256"
        crv = "P-256"
        kid = var.petstore_jwt_public_key.kid
        x   = var.petstore_jwt_public_key.x
        y   = var.petstore_jwt_public_key.y
      },
    ]
  }
}

resource "cloudflare_ruleset" "custom_firewall" {
  zone_id = var.cloudflare_zone_id
  name    = "default"
  kind    = "zone"
  phase   = "http_request_firewall_custom"

  rules = [
    {
      ref         = "petstore_jwt_required"
      description = "Petstore: require a valid JWT on saved operations"
      action      = var.petstore_mitigation_action
      enabled     = false
      expression = join(" and ", [
        "http.host eq \"${var.petstore_hostname}\"",
        "not cf.api_gateway.fallthrough_detected",
        "not (cf.api_gateway.operation_id in {${join(" ", [for k in local.petstore_jwt_exempt_operations : "\"${cloudflare_api_shield_operation.petstore[k].operation_id}\""])}})",
        "not any(cf.api_gateway.tokens.valid[*] == \"${local.petstore_jwt_config_id}\")",
      ])
    },
    {
      ref         = "petstore_schema_violation"
      description = "Petstore: request violates the uploaded OpenAPI schema"
      action      = var.petstore_mitigation_action
      expression  = "http.host eq \"${var.petstore_hostname}\" and cf.schema_validation.uploaded.violated"
    },
    {
      # Sequence fields are only populated once at least one API sequence rule exists (sequence-rules.sh).
      ref         = "petstore_order_requires_inventory"
      description = "Petstore: POST /store/order must follow GET /store/inventory in the same session"
      action      = var.petstore_mitigation_action
      expression = join(" and ", [
        "http.host eq \"${var.petstore_hostname}\"",
        "cf.sequence.current_op eq \"${cloudflare_api_shield_operation.petstore["POST /store/order"].operation_id}\"",
        "not any(cf.sequence.previous_ops[*] == \"${cloudflare_api_shield_operation.petstore["GET /store/inventory"].operation_id}\")",
      ])
    },
    {
      ref         = "petstore_unidentified_endpoint"
      description = "Petstore: request to an API endpoint that is not a saved operation"
      action      = var.petstore_fallthrough_action
      expression  = "http.host eq \"${var.petstore_hostname}\" and starts_with(http.request.uri.path, \"/api/\") and http.request.uri.path ne \"${local.petstore_base_path}/openapi.json\" and cf.api_gateway.fallthrough_detected"
    },
  ]
}

resource "cloudflare_ruleset" "rate_limit" {
  zone_id = var.cloudflare_zone_id
  name    = "default"
  kind    = "zone"
  phase   = "http_ratelimit"

  rules = [
    {
      ref         = "petstore_pet_scraping"
      description = "Petstore: per-user limit on pet lookups (JWT sub)"
      action      = "block"
      expression  = "http.host eq \"${var.petstore_hostname}\" and http.request.method eq \"GET\" and starts_with(http.request.uri.path, \"${local.petstore_base_path}/pet/\")"
      ratelimit = {
        characteristics     = ["cf.colo.id", local.petstore_jwt_sub]
        period              = 10
        requests_per_period = 20
        mitigation_timeout  = 60
      }
    },
  ]
}
