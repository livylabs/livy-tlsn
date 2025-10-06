terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
  # Using local backend for testing
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# TDX-enabled compute instance running TLS Notary server
resource "google_compute_instance" "notary_instance" {
  name         = "${var.environment}-notary-instance"
  machine_type = var.machine_type
  zone         = var.zone

  scheduling {
    on_host_maintenance = "TERMINATE"
  }
  confidential_instance_config {
    enable_confidential_compute = true
    confidential_instance_type  = "TDX"
  }

  boot_disk {
    initialize_params {
      image = var.boot_image
      size  = var.boot_disk_size
      type  = "pd-ssd"
    }
  }

  network_interface {
    network    = google_compute_network.vpc.name
    subnetwork = google_compute_subnetwork.subnet.name
  }

  metadata = {
    environment = var.environment
    user-data = templatefile("${path.module}/cloud-init.yaml", {
      trustauthority_api_key = var.trustauthority_api_key
      environment           = var.environment
      core_script_b64      = base64encode(file("${path.module}/scripts/core.sh"))
      install_script_b64   = base64encode(file("${path.module}/scripts/install.sh"))
      run_script_b64       = base64encode(file("${path.module}/scripts/run.sh"))
    })
  }

  service_account {
    email  = google_service_account.notary_sa.email
    scopes = ["cloud-platform"]
  }

  tags = ["notary-instance", var.environment]

  labels = {
    environment = var.environment
    project     = var.project_name
    workload    = "tls-notary-tdx"
  }
}

# VPC Network
resource "google_compute_network" "vpc" {
  name                    = "${var.environment}-vpc"
  auto_create_subnetworks = false
}

# Subnet
resource "google_compute_subnetwork" "subnet" {
  name                     = "${var.environment}-subnet"
  ip_cidr_range            = var.subnet_cidr
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
}

# Cloud Router for NAT
resource "google_compute_router" "router" {
  name    = "${var.environment}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

# Cloud NAT for internet access without external IP
resource "google_compute_router_nat" "nat" {
  name   = "${var.environment}-nat"
  router = google_compute_router.router.name
  region = var.region

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Firewall rules
resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.environment}-allow-ssh"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = concat(var.allowed_ssh_sources, ["35.235.240.0/20"])  # Include IAP range
  target_tags   = ["notary-instance"]
}

resource "google_compute_firewall" "allow_internal" {
  name    = "${var.environment}-allow-internal"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.subnet_cidr]
}

# Firewall rule for TLS Notary server
resource "google_compute_firewall" "allow_notary" {
  name    = "${var.environment}-allow-notary"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = [tostring(var.tls_notary_port)]
  }

  source_ranges = var.allowed_notary_sources
  target_tags   = ["notary-instance"]
}

# Service Account for TLS Notary instance
resource "google_service_account" "notary_sa" {
  account_id   = "${var.environment}-notary-sa"
  display_name = "TLS Notary Instance Service Account (${var.environment})"
}

# IAM binding for service account
resource "google_project_iam_member" "notary_sa_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.notary_sa.email}"
}

resource "google_project_iam_member" "notary_sa_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.notary_sa.email}"
}
