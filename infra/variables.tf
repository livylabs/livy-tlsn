variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "project_name" {
  description = "Project name for labeling"
  type        = string
  default     = "tls-notary-server"
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP Zone"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Environment name (prod, staging, test)"
  type        = string
  validation {
    condition     = contains(["prod", "staging", "test"], var.environment)
    error_message = "Environment must be either 'prod' or 'staging' or 'test'."
  }
}

variable "machine_type" {
  description = "Machine type for TDX instance running TLS Notary (must support confidential computing)"
  type        = string
  default     = "c3-standard-4"
  validation {
    condition     = can(regex("^c3-", var.machine_type))
    error_message = "Machine type must be C3 series for Intel TDX support (e.g., c3-standard-4)."
  }
}

variable "boot_image" {
  description = "Boot disk image (Ubuntu 24.04+ recommended for TDX)"
  type        = string
  default     = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
}

variable "boot_disk_size" {
  description = "Boot disk size in GB"
  type        = number
  default     = 20
}

variable "subnet_cidr" {
  description = "CIDR block for subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "allowed_ssh_sources" {
  description = "List of CIDR blocks allowed to SSH"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "tls_notary_version" {
  description = "TLS Notary server version to deploy"
  type        = string
  default     = "latest"
}

variable "tls_notary_port" {
  description = "Port for TLS Notary server"
  type        = number
  default     = 7047
}

variable "trustauthority_api_key" {
  description = "Intel Trust Authority API key for attestation"
  type        = string
  sensitive   = true
}

variable "allowed_notary_sources" {
  description = "List of CIDR blocks allowed to access TLS Notary server"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
