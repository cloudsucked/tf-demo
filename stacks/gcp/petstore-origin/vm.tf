resource "google_service_account" "petstore" {
  account_id   = "petstore-origin"
  display_name = "Petstore API Shield demo origin"
}

resource "google_project_iam_member" "petstore" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ])

  project = var.gcp_project_id
  role    = each.value
  member  = google_service_account.petstore.member
}

resource "google_secret_manager_secret" "tunnel_token" {
  secret_id = "petstore-cloudflared-token"

  replication {
    auto {}
  }

  depends_on = [google_project_service.this]
}

resource "google_secret_manager_secret_version" "tunnel_token" {
  secret      = google_secret_manager_secret.tunnel_token.id
  secret_data = data.terraform_remote_state.account.outputs.petstore_tunnel_token
}

resource "google_secret_manager_secret_iam_member" "tunnel_token" {
  secret_id = google_secret_manager_secret.tunnel_token.id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.petstore.member
}

resource "google_compute_instance" "petstore" {
  name                      = "petstore-origin"
  machine_type              = var.machine_type
  zone                      = var.gcp_zone
  tags                      = ["petstore-origin"]
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "cos-cloud/cos-stable"
      size  = 10
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.petstore.id
  }

  service_account {
    email  = google_service_account.petstore.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "TRUE"
    google-logging-enabled = "true"
    user-data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
      petstore_image       = var.petstore_image
      cloudflared_image    = var.cloudflared_image
      tunnel_token_version = "${google_secret_manager_secret.tunnel_token.id}/versions/latest"
    })
  }

  depends_on = [
    google_compute_router_nat.petstore,
    google_secret_manager_secret_iam_member.tunnel_token,
    google_secret_manager_secret_version.tunnel_token,
  ]
}
