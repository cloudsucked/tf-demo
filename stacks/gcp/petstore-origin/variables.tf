variable "gcp_project_id" {
  description = "GCP project hosting the Petstore origin VM."
  type        = string
}

variable "gcp_region" {
  description = "GCP region for the network and Cloud NAT."
  type        = string
  default     = "europe-west1"
}

variable "gcp_zone" {
  description = "GCP zone for the origin VM."
  type        = string
  default     = "europe-west1-b"
}

variable "machine_type" {
  description = "Machine type for the origin VM."
  type        = string
  default     = "e2-small"
}

variable "hcp_organization" {
  description = "HCP Terraform organization holding the account stack state (tunnel token)."
  type        = string
}

variable "account_workspace" {
  description = "HCP Terraform workspace of the account stack (read for the tunnel token)."
  type        = string
  default     = "orangecloud"
}

variable "petstore_image" {
  description = "Swagger Petstore v3 container image."
  type        = string
  default     = "swaggerapi/petstore3:1.0.28"
}

variable "cloudflared_image" {
  description = "cloudflared container image."
  type        = string
  default     = "cloudflare/cloudflared:latest"
}
