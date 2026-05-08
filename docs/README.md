# Livy TLSNotary Docs

Documentation app for the Livy TLSNotary TEE work. It covers the `livylabs/tlsn` `tee_dev` implementation, deployed GCP infrastructure, Intel TDX attestation, examples, and operational runbooks.

## Develop

```bash
pnpm dev
```

Open `http://localhost:3000`.

## Check

```bash
pnpm types:check
pnpm lint
```

## Content

Documentation pages live in `content/docs`.

- Deployment runbooks: `content/docs/deployment`
- Example docs: `content/docs/examples`
- Security docs: `content/docs/security`
