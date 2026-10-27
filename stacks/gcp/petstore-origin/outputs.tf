output "instance_name" {
  description = "Petstore origin VM name."
  value       = google_compute_instance.petstore.name
}

output "ssh_command" {
  description = "SSH to the origin VM through IAP (no public IP)."
  value       = "gcloud compute ssh ${google_compute_instance.petstore.name} --zone ${var.gcp_zone} --project ${var.gcp_project_id} --tunnel-through-iap"
}
