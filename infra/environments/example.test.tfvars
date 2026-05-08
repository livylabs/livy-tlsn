environment    = "test"
project_id     = "livy-infra"
project_name   = "tls-notary-server"
region         = "us-central1"
zone           = "us-central1-a"
machine_type   = "c3-standard-4"
boot_disk_size = 30
subnet_cidr    = "10.0.1.0/24"
allowed_ssh_sources = [
  "0.0.0.0/0"
]
tls_notary_version = "latest"
tlsn_branch        = "benchmark"
tls_notary_port    = 7047
allowed_notary_sources = [
  "0.0.0.0/0"
]

# Intel Trust Authority API key
# trustauthority_api_key = "your_api_key_here"

# Domain name for HTTPS setup
domain_name       = "your-domain.com"
certificate_email = "contact@livylabs.xyz"
