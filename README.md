# Livy TLSN TDX Infrastructure

Terraform infrastructure for deploying a TLS Notary server on Google Cloud with Intel TDX confidential computing and Intel Trust Authority attestation.

The deploy is intended to be single-command after configuration:

```bash
cd infra
terraform apply -var-file="environments/test.tfvars" -auto-approve
```

Terraform creates the infrastructure, writes the cloud-init payload to the VM, and cloud-init runs the bootstrap scripts automatically. Normal deployments should not require SSHing into the instance or running setup scripts by hand.

For the full step-by-step deployment instructions, see [instructions.md](instructions.md). The docs app version is [Terraform GCP Deployment](docs/content/docs/deployment/terraform-gcp.mdx).

## What It Deploys

- A TDX-enabled Ubuntu 24.04 Compute Engine VM.
- A custom VPC, subnet, Cloud Router, and Cloud NAT.
- Firewall rules for SSH, internal traffic, TLS Notary, HTTP, and HTTPS.
- A VM service account with Logging and Monitoring writer roles.
- TLS Notary server built from the `livylabs/tlsn` `tee_dev` branch.
- TLS Notary TEE proxy for prove/attestation flows.
- Nginx reverse proxy.
- Optional Let's Encrypt HTTPS when `domain_name` resolves to the VM external IP.

## Bootstrap Flow

Cloud-init writes the required config and scripts to the VM, then runs:

```text
/opt/scripts/core.sh
/opt/scripts/install.sh
/opt/scripts/run.sh
/opt/scripts/setup-https.sh
```

The scripts are idempotent and fail at the real failing step. Their responsibilities are:

- `core.sh`: install host packages, install Rust, install Intel Trust Authority CLI, verify TDX, configure `trustauthority-cli` access.
- `install.sh`: create TLS Notary config, clone/update `livylabs/tlsn`, build `notary-server` and the TEE proxy.
- `run.sh`: write systemd units, start and enable `tls-notary-server` and `tls-notary-proxy`, wait for local health checks.
- `setup-https.sh`: configure Nginx, proxy traffic to the services, and request a Let's Encrypt certificate only when DNS already points at the instance IP.

## Requirements

- Google Cloud project with billing enabled.
- `gcloud` authenticated for the target project.
- Application Default Credentials configured for Terraform.
- Terraform installed locally.
- Intel Trust Authority API key.
- Optional DNS A record for HTTPS.

For the current test environment:

```bash
gcloud config set project livy-infra
gcloud auth application-default set-quota-project livy-infra
```

## Configuration

Create a local tfvars file:

```bash
cp infra/environments/example.test.tfvars infra/environments/test.tfvars
```

Set at least:

```hcl
project_id = "livy-infra"

trustauthority_api_key = "your Intel Trust Authority API key"
domain_name            = "tlsn.livylabs.xyz"
certificate_email      = "contact@livylabs.xyz"
```

`infra/environments/test.tfvars` is gitignored because it contains secrets.

## Deploy

```bash
cd infra
terraform init
terraform apply -var-file="environments/test.tfvars" -auto-approve
```

After apply, Terraform outputs the VM IP, HTTP endpoint, HTTPS endpoint, SSH command, and Intel Trust Authority test commands.

Current test deployment:

```text
https://tlsn.livylabs.xyz/healthcheck
```

Expected response:

```text
Ok
```

## DNS And Destroy/Apply

The current Terraform uses an ephemeral external IP:

```hcl
access_config {}
```

That means a `terraform destroy` followed by `terraform apply` can assign a different IP. The services should still deploy, but HTTPS will only configure automatically if `domain_name` resolves to the new VM IP before `setup-https.sh` runs.

For a fully repeatable destroy/apply flow with HTTPS, add a reserved static IP resource and attach it to the VM, then point DNS at that static IP once.

If DNS is not ready during first boot, `setup-https.sh` leaves Nginx HTTP proxying configured and skips certificate issuance without failing the whole bootstrap.

## Useful Commands

Check Terraform state:

```bash
cd infra
terraform plan -var-file="environments/test.tfvars"
```

Check whether the VM bootstrap is still running:

```bash
gcloud compute ssh test-notary-instance --zone=us-central1-a --project=livy-infra \
  --command="sudo cloud-init status --long"
```

Interpretation:

- `status: running`: cloud-init is still running the install scripts. This is expected while packages install and Rust builds TLSN.
- `status: done`: bootstrap finished.
- `status: error`: bootstrap failed. Check the cloud-init log.

Wait until bootstrap exits:

```bash
gcloud compute ssh test-notary-instance --zone=us-central1-a --project=livy-infra \
  --command="sudo cloud-init status --wait"
```

Watch bootstrap logs live:

```bash
gcloud compute ssh test-notary-instance --zone=us-central1-a --project=livy-infra \
  --command="sudo tail -f /var/log/cloud-init-output.log"
```

Check services:

```bash
gcloud compute ssh test-notary-instance --zone=us-central1-a --project=livy-infra \
  --command="systemctl is-active tls-notary-server tls-notary-proxy nginx"
```

Check logs:

```bash
gcloud compute ssh test-notary-instance --zone=us-central1-a --project=livy-infra \
  --command="sudo journalctl -u tls-notary-server -u tls-notary-proxy --no-pager -n 100"
```

## Cleanup

```bash
cd infra
terraform destroy -var-file="environments/test.tfvars"
```

This deletes the managed VM, network resources, firewall rules, service account bindings, and local Terraform-managed infrastructure.

## References

- [TLSNotary Documentation](https://tlsnotary.org/docs/notary_server)
- [Intel Trust Authority](https://docs.trustauthority.intel.com/main/articles/articles/ita/tutorial-tdx-gcp.html)
- [Intel TDX Overview](https://www.intel.com/content/www/us/en/developer/articles/technical/intel-trust-domain-extensions.html)
- [Google Cloud Confidential Computing](https://cloud.google.com/confidential-computing)
