resource "google_compute_network" "petstore" {
  name                    = "petstore-demo"
  auto_create_subnetworks = false

  depends_on = [google_project_service.this]
}

resource "google_compute_subnetwork" "petstore" {
  name                     = "petstore-demo-${var.gcp_region}"
  network                  = google_compute_network.petstore.id
  region                   = var.gcp_region
  ip_cidr_range            = "10.10.0.0/24"
  private_ip_google_access = true
}

# The VM has no external IP; Cloud NAT provides egress for image pulls and the tunnel.
resource "google_compute_router" "petstore" {
  name    = "petstore-demo"
  network = google_compute_network.petstore.id
  region  = var.gcp_region
}

resource "google_compute_router_nat" "petstore" {
  name                               = "petstore-demo"
  router                             = google_compute_router.petstore.name
  region                             = var.gcp_region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# No inbound application traffic is allowed; only SSH through IAP for troubleshooting.
resource "google_compute_firewall" "iap_ssh" {
  name          = "petstore-demo-allow-iap-ssh"
  network       = google_compute_network.petstore.id
  direction     = "INGRESS"
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["petstore-origin"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
