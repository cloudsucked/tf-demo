terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.28"
    }
  }
}

# Use a sensitive token input from the local, ignored terraform.tfvars file.
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

locals {
  account_id = var.cloudflare_account_id
}
