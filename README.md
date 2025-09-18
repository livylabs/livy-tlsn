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

## Prerequisites

1. **Google Cloud Platform Account** with billing enabled
2. **Intel Trust Authority API Key** - Get from [Intel Trust Authority Portal](https://portal.trustauthority.intel.com)
3. **Terraform** >= 1.0 installed locally
4. **gcloud CLI** installed and authenticated

## Quick Start

### 1. Clone Repository
```bash
git clone https://github.com/livylabs/livy-tlsn.git
cd livy-tlsn/infra
```

### 2. Configure Variables
Copy `environments/example.test.tfvars` to `environments/test.tfvars` and Intel Trust Authority API key:
```hcl
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
```

### 3. Deploy Infrastructure

If you haven't already, log in to Google Cloud:
```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project livy-infra
```

Deploy infrastructure:
```bash
# Initialize Terraform
terraform init

# Plan deployment
terraform plan -var-file="environments/test.tfvars"

# Deploy infrastructure
terraform apply -var-file="environments/test.tfvars"
```

**Deployment Time**: The full deployment takes approximately 5-7 minutes:
- Infrastructure creation: ~2 minutes
- Instance boot + cloud-init: ~3-5 minutes

### 4. **Tests**

Run the automated test suite to verify your deployment:

```bash
# Run comprehensive test suite
./test-deployment.sh
```

**Note**: If TLSn health check fails after deployment, it may be because the service is not yet running. Wait a few minutes and rerun the test.

## File Locations

| File | Location | Purpose |
|------|----------|---------|
| TLSn Binary | `/home/livy/src/tlsn/target/release/notary-server` | Compiled notary server |
| TLSn Config | `/home/livy/tls-notary-config/config.toml` | Server configuration |
| Signing Key | `/home/livy/tls-notary-config/notary-signing-key.pem` | Notary signing key |
| Intel TA Config | `/home/livy/config.json` | Trust Authority configuration |
| Service File | `/etc/systemd/system/tls-notary-server.service` | Systemd service definition |
| Source Code | `/home/livy/src/tlsn/` | TLSn source code |

## Cleanup

To destroy the infrastructure:

```bash
terraform destroy -var-file="environments/test.tfvars"
```

## References

- [TLSNotary Documentation](https://tlsnotary.org/docs/notary_server)
- [Intel Trust Authority](https://docs.trustauthority.intel.com/main/articles/articles/ita/tutorial-tdx-gcp.html)
