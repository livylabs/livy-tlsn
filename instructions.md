# Livy TLSN Terraform Deployment

This repository deploys a TLS Notary server on Google Cloud using Terraform and cloud-init.
`terraform apply` creates or updates the infrastructure, then the VM runs the bootstrap scripts automatically.
You should not need to SSH into the VM or run the scripts manually for a normal deploy.

## Prerequisites

- Google Cloud project with billing enabled.
- `gcloud` authenticated for the target project.
- Application Default Credentials configured for Terraform.
- Terraform installed locally.
- Intel Trust Authority API key.
- Optional but recommended: a DNS A record for `domain_name` that already points at the VM external IP.

For this test environment, the project is:

```bash
gcloud config set project livy-infra
gcloud auth application-default set-quota-project livy-infra
```

## Configuration

Create a local tfvars file from the example:

```bash
cp infra/environments/example.test.tfvars infra/environments/test.tfvars
```

Set these values in `infra/environments/test.tfvars`:

```hcl
project_id = "livy-infra"

trustauthority_api_key = "your Intel Trust Authority API key"
domain_name            = "tlsn.livylabs.xyz"
certificate_email      = "contact@livylabs.xyz"
```

`infra/environments/test.tfvars` is ignored by git because it contains secrets.

## Deploy

Run Terraform from `infra`:

```bash
cd infra
terraform init
terraform apply -var-file="environments/test.tfvars" -auto-approve
```

Terraform creates the GCP resources and writes the cloud-init payload into the VM metadata.
On first boot, cloud-init runs:

```text
/opt/scripts/core.sh
/opt/scripts/install.sh
/opt/scripts/run.sh
/opt/scripts/setup-https.sh
```

## What Terraform Creates

- A TDX-enabled Compute Engine VM named `${environment}-notary-instance`.
- A custom VPC named `${environment}-vpc`.
- A subnet named `${environment}-subnet`.
- A Cloud Router and Cloud NAT for outbound internet access.
- Firewall rules for SSH, internal traffic, the TLS Notary port, HTTP, and HTTPS.
- A service account named `${environment}-notary-sa`.
- Logging and Monitoring IAM roles for the service account.

The VM runs Ubuntu 24.04 with Intel TDX confidential compute enabled.

## What The Scripts Do

`core.sh` prepares the host:

- Installs OS build dependencies.
- Fixes `/home/livy` ownership.
- Verifies `/dev/tdx_guest` and kernel TDX state.
- Installs Rust.
- Installs Intel Trust Authority CLI.
- Validates `/home/livy/config.json`.
- Configures restricted passwordless sudo for `trustauthority-cli`.

`install.sh` builds TLSN:

- Creates `/home/livy/tls-notary-config`.
- Creates the notary config and signing key if missing.
- Clones or updates `https://github.com/livylabs/tlsn.git` on branch `tee_dev`.
- Builds `notary-server` and the `notary-tee` proxy example in release mode.

`run.sh` starts services:

- Writes systemd units for `tls-notary-server` and `tls-notary-proxy`.
- Starts and enables both services.
- Waits for local health checks on ports `7047` and `7048`.

`setup-https.sh` configures ingress:

- Installs Nginx and Certbot.
- Proxies `/healthcheck` and normal notary traffic to `127.0.0.1:7047`.
- Proxies `/api/v1/prove` and job artifact endpoints to `127.0.0.1:7048`.
- If `domain_name` is set and resolves to the VM external IP, requests a Let's Encrypt certificate and enables HTTPS.
- If DNS is not ready, leaves HTTP proxying configured and skips certificate issuance without failing the whole bootstrap.

## DNS And HTTPS

For automatic HTTPS on the first apply, `domain_name` must resolve to the VM external IP before `setup-https.sh` runs.
In the current test deployment, `tlsn.livylabs.xyz` resolves to `34.30.152.37`.

If the domain does not resolve to the instance IP yet, the VM still deploys and Nginx serves HTTP.
For a deploy that needs no manual VM commands, point DNS at the instance IP before the VM's first bootstrap.
If DNS is added later, only `setup-https.sh` needs to be rerun.

## Outputs

After apply, Terraform prints:

- `instance_external_ip`
- `tls_notary_endpoint`
- `tls_notary_https_endpoint`
- `livy_ssh_command`
- Intel Trust Authority evidence/token test commands

Expected health check after HTTPS is configured:

```bash
curl https://tlsn.livylabs.xyz/healthcheck
```

Expected response:

```text
Ok
```

## Bootstrap Status

After `terraform apply`, the VM may still be running cloud-init. Check the status with:

```bash
gcloud compute ssh test-notary-instance --zone=us-central1-a --project=livy-infra \
  --command="sudo cloud-init status --long"
```

Status meanings:

- `status: running`: installation is still in progress. This is normal while packages install and TLSN builds.
- `status: done`: installation finished.
- `status: error`: installation failed. Check `/var/log/cloud-init-output.log`.

Wait for completion:

```bash
gcloud compute ssh test-notary-instance --zone=us-central1-a --project=livy-infra \
  --command="sudo cloud-init status --wait"
```

Follow the install log:

```bash
gcloud compute ssh test-notary-instance --zone=us-central1-a --project=livy-infra \
  --command="sudo tail -f /var/log/cloud-init-output.log"
```
