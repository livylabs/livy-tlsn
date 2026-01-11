# Livy TLSn TDX Infrastructure

This repository contains Terraform infrastructure for deploying a TLS Notary server on Google Cloud Platform with Intel TDX (Trust Domain Extensions) confidential computing capabilities and Intel Trust Authority attestation.

## Overview

This infrastructure deploys:
- **TDX-enabled GCP instance** running Ubuntu 24.04 LTS
- **TLS Notary server** built from source
- **Intel Trust Authority integration** for hardware attestation
- **Auto-configuration** via cloud-init on boot
- **Systemd service** for TLSn server management

## Architecture

```

**Important**: The `domain_name` variable determines:
- HTTPS endpoint URL: `https://${domain_name}`
- SSL certificate path: `/etc/letsencrypt/live/${domain_name}/`
- Nginx server configuration
┌─────────────────────────────────────────────────────────────┐
│                    Google Cloud Platform                    │
│                                                             │
│  ┌─────────────────┐    ┌─────────────────────────────────┐ │
│  │   VPC Network   │    │        TDX Instance             │ │
│  │                 │    │                                 │ │
│  │ ┌─────────────┐ │    │ ┌─────────────────────────────┐ │ │
│  │ │   Subnet    │ │◄───┤ │     Ubuntu 24.04 LTS        │ │ │
│  │ │ 10.0.1.0/24 │ │    │ │                             │ │ │
│  │ └─────────────┘ │    │ │ ┌─────────────────────────┐ │ │ │
│  │                 │    │ │ │   TLS Notary Server     │ │ │ │
│  │ ┌─────────────┐ │    │ │ │   (Native Binary)       │ │ │ │
│  │ │ Cloud NAT   │ │    │ │ │   Port: 7047            │ │ │ │
│  │ └─────────────┘ │    │ │ └─────────────────────────┘ │ │ │
│  └─────────────────┘    │ │                             │ │ │
│                         │ │ ┌─────────────────────────┐ │ │ │
│                         │ │ │ Intel Trust Authority   │ │ │ │
│                         │ │ │ CLI + Attestation       │ │ │ │
│                         │ │ └─────────────────────────┘ │ │ │
│                         │ └─────────────────────────────┘ │ │
│                         └─────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

**Important**: The `domain_name` variable determines:
- HTTPS endpoint URL: `https://${domain_name}`
- SSL certificate path: `/etc/letsencrypt/live/${domain_name}/`
- Nginx server configuration

## Prerequisites

1. **Google Cloud Platform Account** with billing enabled
2. **Intel Trust Authority API Key** - Get from [Intel Trust Authority Portal](https://portal.trustauthority.intel.com)
3. **Terraform** >= 1.0 installed locally
4. **gcloud CLI** installed and authenticated

## Quick Start

### 1. Clone Repository
```bash

**Important**: The `domain_name` variable determines:
- HTTPS endpoint URL: `https://${domain_name}`
- SSL certificate path: `/etc/letsencrypt/live/${domain_name}/`
- Nginx server configuration
git clone https://github.com/livylabs/livy-tlsn.git
cd livy-tlsn/infra
```

**Important**: The `domain_name` variable determines:
- HTTPS endpoint URL: `https://${domain_name}`
- SSL certificate path: `/etc/letsencrypt/live/${domain_name}/`
- Nginx server configuration

### 2. Configure Variables
Copy `environments/example.test.tfvars` to `environments/test.tfvars` and Intel Trust Authority API key:
environment      = "test"
project_id       = "your-gcp-project-id"
project_name     = "tls-notary-server"
region           = "us-central1"
zone             = "us-central1-a"
machine_type     = "c3-standard-4"  # TDX-enabled instance
boot_disk_size   = 30
subnet_cidr      = "10.0.1.0/24"
allowed_ssh_sources = [
  "0.0.0.0/0"  # Restrict this in production
]
tls_notary_version = "latest"
tls_notary_port    = 7047
allowed_notary_sources = [
  "0.0.0.0/0"  # Restrict this in production
]

# Intel Trust Authority API key
trustauthority_api_key = "your_api_key_here"
domain_name = "your-domain.com"  # Change this to your domain
```

**Important**: The `domain_name` variable determines:
- HTTPS endpoint URL: `https://${domain_name}`
- SSL certificate path: `/etc/letsencrypt/live/${domain_name}/`
- Nginx server configuration

### 3. Authenticate with Google Cloud

Before deploying, authenticate with Google Cloud Platform:

```bash

**Important**: The `domain_name` variable determines:
- HTTPS endpoint URL: `https://${domain_name}`
- SSL certificate path: `/etc/letsencrypt/live/${domain_name}/`
- Nginx server configuration
# Authenticate your user account
gcloud auth login

# Set up application default credentials for Terraform
gcloud auth application-default login

# Set your project (replace with your actual project ID)
gcloud config set project your-gcp-project-id
```

**Important**: The `domain_name` variable determines:
- HTTPS endpoint URL: `https://${domain_name}`
- SSL certificate path: `/etc/letsencrypt/live/${domain_name}/`
- Nginx server configuration

### 4. Deploy Infrastructure

```bash

**Important**: The `domain_name` variable determines:
- HTTPS endpoint URL: `https://${domain_name}`
- SSL certificate path: `/etc/letsencrypt/live/${domain_name}/`
- Nginx server configuration
# Navigate to infrastructure directory
cd infra

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var-file="environments/test.tfvars"

# Deploy infrastructure (auto-approve for non-interactive deployment)
terraform apply -var-file="environments/test.tfvars" -auto-approve
```

**Important**: The `domain_name` variable determines:
- HTTPS endpoint URL: `https://${domain_name}`
- SSL certificate path: `/etc/letsencrypt/live/${domain_name}/`
- Nginx server configuration

**Deployment Timeline**: The full deployment takes approximately 8-10 minutes:
- Infrastructure creation: ~2 minutes
- Instance boot: ~1 minute
- Cloud-init setup: ~2 minutes
- Rust compilation: ~4-5 minutes
- Service startup: ~1 minute

### 5. Verify Deployment

#### Automated Testing

Run the comprehensive test suite to verify your deployment:

```bash

**Important**: The `domain_name` variable determines:
- HTTPS endpoint URL: `https://${domain_name}`
- SSL certificate path: `/etc/letsencrypt/live/${domain_name}/`
- Nginx server configuration
# Return to project root and run tests
cd ..
./test-deployment.sh
```

**Important**: The `domain_name` variable determines:
- HTTPS endpoint URL: `https://${domain_name}`
- SSL certificate path: `/etc/letsencrypt/live/${domain_name}/`
- Nginx server configuration

**Expected Test Results**:
- ✅ Infrastructure Health: Instance is RUNNING
- ✅ TLSn Service Status: Service is active
- ✅ Health Endpoint: Returns "Ok"
- ✅ TDX Status: Intel TDX memory encryption active
- ✅ Native Binary: Compiled binary exists and is executable
- ✅ Process Memory Usage: Service running natively
- ✅ Service Logs: Recent activity detected
- ✅ Intel Trust Authority CLI: Installed and configured

#### Manual Testing

You can also test the service manually:

```bash

**Important**: The `domain_name` variable determines:
- HTTPS endpoint URL: `https://${domain_name}`
- SSL certificate path: `/etc/letsencrypt/live/${domain_name}/`
- Nginx server configuration
# Get the external IP from Terraform output
terraform output -raw instance_external_ip

# Test the health endpoint directly
curl http://EXTERNAL_IP:7047/healthcheck
# Expected response: "Ok"

# Access the web interface
open http://EXTERNAL_IP:7047
```

**Important**: The `domain_name` variable determines:
- HTTPS endpoint URL: `https://${domain_name}`
- SSL certificate path: `/etc/letsencrypt/live/${domain_name}/`
- Nginx server configuration

### 6. Access the TLS Notary Server

#### Web Interface

The TLS Notary server provides a simple web interface at:
- **HTTP**: `http://EXTERNAL_IP:7047`
- **HTTPS**: `https://tlsn.livylabs.xyz` (if DNS is configured)

The interface displays:
- Server version information
- Public key for cryptographic verification
- Git commit hash
- Health check endpoint
- Server information endpoint

#### API Endpoints

| Endpoint | Purpose | Response |
|----------|---------|----------|
| `/healthcheck` | Service health status | `"Ok"` |
| `/info` | Server information | JSON with server details |
| `/` | Web interface | HTML page with server info |

#### Service Architecture

The deployed service includes:
- **TLS Notary Server**: Core notarization service on port 7047
- **Nginx Reverse Proxy**: HTTPS termination and load balancing
- **Intel TDX**: Hardware-based confidential computing
- **Intel Trust Authority**: Hardware attestation and verification
- **Systemd Service**: Automatic service management and restart

## File Locations

| File | Location | Purpose |
|------|----------|---------|
| TLSn Binary | `/home/livy/src/tlsn/target/release/notary-server` | Compiled notary server |
| TLSn Config | `/home/livy/tls-notary-config/config.toml` | Server configuration |
| Signing Key | `/home/livy/tls-notary-config/notary-signing-key.pem` | Notary signing key |
| Intel TA Config | `/home/livy/config.json` | Trust Authority configuration |
| Service File | `/etc/systemd/system/tls-notary-server.service` | Systemd service definition |
| Source Code | `/home/livy/src/tlsn/` | TLSn source code |
| Nginx Config | `/etc/nginx/sites-available/tlsn` | HTTPS proxy configuration |
| SSL Certificates | `/etc/letsencrypt/live/${domain_name}/` | Let's Encrypt certificates (dynamic based on domain_name variable) |

## Troubleshooting

### Common Issues

#### Service Not Starting
```bash

**Important**: The `domain_name` variable determines:
- HTTPS endpoint URL: `https://${domain_name}`
- SSL certificate path: `/etc/letsencrypt/live/${domain_name}/`
- Nginx server configuration
# Check service status
gcloud compute ssh test-notary-instance --zone=us-central1-a --command="sudo systemctl status tls-notary-server"

# Check logs
gcloud compute ssh test-notary-instance --zone=us-central1-a --command="sudo journalctl -u tls-notary-server -f"
```

**Important**: The `domain_name` variable determines:
- HTTPS endpoint URL: `https://${domain_name}`
- SSL certificate path: `/etc/letsencrypt/live/${domain_name}/`
- Nginx server configuration

#### Build Failures
```bash

**Important**: The `domain_name` variable determines:
- HTTPS endpoint URL: `https://${domain_name}`
- SSL certificate path: `/etc/letsencrypt/live/${domain_name}/`
- Nginx server configuration
# Check cloud-init logs
gcloud compute ssh test-notary-instance --zone=us-central1-a --command="sudo tail -100 /var/log/cloud-init-output.log"

# Check if build is still running
gcloud compute ssh test-notary-instance --zone=us-central1-a --command="ps aux | grep cargo"
```

**Important**: The `domain_name` variable determines:
- HTTPS endpoint URL: `https://${domain_name}`
- SSL certificate path: `/etc/letsencrypt/live/${domain_name}/`
- Nginx server configuration

#### HTTPS Certificate Issues
```bash

**Important**: The `domain_name` variable determines:
- HTTPS endpoint URL: `https://${domain_name}`
- SSL certificate path: `/etc/letsencrypt/live/${domain_name}/`
- Nginx server configuration
# Check nginx status
gcloud compute ssh test-notary-instance --zone=us-central1-a --command="sudo systemctl status nginx"

# Check certificate status
gcloud compute ssh test-notary-instance --zone=us-central1-a --command="sudo certbot certificates"
```

**Important**: The `domain_name` variable determines:
- HTTPS endpoint URL: `https://${domain_name}`
- SSL certificate path: `/etc/letsencrypt/live/${domain_name}/`
- Nginx server configuration

### Performance Monitoring

```bash

**Important**: The `domain_name` variable determines:
- HTTPS endpoint URL: `https://${domain_name}`
- SSL certificate path: `/etc/letsencrypt/live/${domain_name}/`
- Nginx server configuration
# Check resource usage
gcloud compute ssh test-notary-instance --zone=us-central1-a --command="htop"

# Monitor TLS Notary logs
gcloud compute ssh test-notary-instance --zone=us-central1-a --command="sudo journalctl -u tls-notary-server -f"
```

**Important**: The `domain_name` variable determines:
- HTTPS endpoint URL: `https://${domain_name}`
- SSL certificate path: `/etc/letsencrypt/live/${domain_name}/`
- Nginx server configuration

## Cleanup

To destroy the infrastructure:

```bash

**Important**: The `domain_name` variable determines:
- HTTPS endpoint URL: `https://${domain_name}`
- SSL certificate path: `/etc/letsencrypt/live/${domain_name}/`
- Nginx server configuration
cd infra
terraform destroy -var-file="environments/test.tfvars"
```

**Important**: The `domain_name` variable determines:
- HTTPS endpoint URL: `https://${domain_name}`
- SSL certificate path: `/etc/letsencrypt/live/${domain_name}/`
- Nginx server configuration

**Warning**: This will permanently delete all resources including the instance, VPC, and any stored data.

## References

- [TLSNotary Documentation](https://tlsnotary.org/docs/notary_server)
- [Intel Trust Authority](https://docs.trustauthority.intel.com/main/articles/articles/ita/tutorial-tdx-gcp.html)
- [Intel TDX Overview](https://www.intel.com/content/www/us/en/developer/articles/technical/intel-trust-domain-extensions.html)
- [Google Cloud Confidential Computing](https://cloud.google.com/confidential-computing)