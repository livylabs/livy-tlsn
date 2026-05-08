output "instance_name" {
  description = "Name of the TDX instance"
  value       = google_compute_instance.notary_instance.name
}

output "instance_id" {
  description = "ID of the TDX instance"
  value       = google_compute_instance.notary_instance.instance_id
}

output "instance_external_ip" {
  description = "External IP address of the TDX instance"
  value       = try(google_compute_instance.notary_instance.network_interface[0].access_config[0].nat_ip, "No external IP")
}

output "instance_internal_ip" {
  description = "Internal IP address of the TDX instance"
  value       = google_compute_instance.notary_instance.network_interface[0].network_ip
}

output "vpc_name" {
  description = "Name of the VPC"
  value       = google_compute_network.vpc.name
}

output "subnet_name" {
  description = "Name of the subnet"
  value       = google_compute_subnetwork.subnet.name
}

output "service_account_email" {
  description = "Email of the service account"
  value       = google_service_account.notary_sa.email
}

output "livy_ssh_command" {
  description = "SSH command to connect to Livy TDX instance"
  value       = "gcloud compute ssh ${google_compute_instance.notary_instance.name} --zone=${var.zone}"
}

output "trustauthority_evidence_test" {
  description = "Command to test Intel Trust Authority evidence collection"
  value       = "gcloud compute ssh ${google_compute_instance.notary_instance.name} --zone=${var.zone} --command='sudo trustauthority-cli evidence --tdx --tpm -c /home/livy/config.json'"
}

output "trustauthority_token_test" {
  description = "Command to test Intel Trust Authority token generation"
  value       = "gcloud compute ssh ${google_compute_instance.notary_instance.name} --zone=${var.zone} --command='sudo trustauthority-cli token --tdx --tpm -c /home/livy/config.json'"
}

output "tls_notary_endpoint" {
  description = "TLS Notary server endpoint URL"
  value       = try("http://${google_compute_instance.notary_instance.network_interface[0].access_config[0].nat_ip}:${var.tls_notary_port}", "No external IP configured")
}

output "tls_notary_https_endpoint" {
  description = "TLS Notary server HTTPS endpoint URL"
  value       = var.domain_name != "" ? "https://${var.domain_name}" : "Domain not configured"
}
