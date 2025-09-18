# TDX + Intel Trust Authority Attestation

This repository contains Terraform configuration to deploy a TDX-enabled GCP instance running TLS Notary server with Intel Trust Authority attestation.

## Features

- **Intel TDX Confidential VM** - Hardware-level memory encryption
- **Intel Trust Authority CLI** - Complete TDX + vTPM attestation
- **TLS Notary Server** - Running in confidential environment
- **Environment Variable API Key** - Secure API key management

## Prerequisites

- GCP project with billing enabled
- `gcloud` CLI installed and authenticated
- Terraform installed
- Intel Trust Authority API key

## Deployment

1. Clone this repository
2. Set your GCP project ID in `environments/test.tfvars`
3. Set your Intel Trust Authority API key:
   ```bash
   export TF_VAR_trustauthority_api_key="your_api_key_here"
   ```
4. Deploy the infrastructure:
   ```bash
   terraform init
   terraform plan -var-file=environments/test.tfvars
   terraform apply -var-file=environments/test.tfvars
   ```

## Usage

After deployment, SSH into the instance:
```bash
gcloud compute ssh test-notary-instance --zone=us-central1-a
```

### Intel Trust Authority Commands

- **Generate complete attestation token**: `sudo trustauthority-cli token --tdx --tpm -c /home/livy/config.json`
- **Collect raw evidence**: `sudo trustauthority-cli evidence --tdx --tpm -c /home/livy/config.json`
- **Verify token**: `trustauthority-cli verify --token "JWT_TOKEN" --config /home/livy/config.json`
- **Include UEFI event logs**: `sudo trustauthority-cli token --tdx --tpm --ccel -c /home/livy/config.json`

### TLS Notary Server

- **Health check**: `curl http://localhost:7047/healthcheck`
- **Container logs**: `sudo -u livy docker logs tls-notary-server`
- **Container status**: `sudo -u livy docker ps --filter name=tls-notary-server`

## What You Get

The instance provides:
- **Complete TDX + vTPM attestation** - Cryptographically signed evidence
- **PCR measurements** - Boot-time verification
- **Platform certificates** - Google Cloud attestation
- **Intel Trust Authority signature** - Remote verification
- **TLS Notary server** - Running in confidential environment

## Cleanup

To destroy the infrastructure:
```bash
terraform destroy -var-file=environments/test.tfvars
```