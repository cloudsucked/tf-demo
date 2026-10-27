terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.7.0"
    }
  }
}

# Authenticate with Application Default Credentials (gcloud auth application-default login).
provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

data "terraform_remote_state" "account" {
  backend = "remote"

  config = {
    organization = var.hcp_organization
    workspaces = {
      name = var.account_workspace
    }
  }
}

resource "google_project_service" "this" {
  for_each = toset([
    "compute.googleapis.com",
    "iap.googleapis.com",
    "secretmanager.googleapis.com",
  ])

  service            = each.value
  disable_on_destroy = false
}
