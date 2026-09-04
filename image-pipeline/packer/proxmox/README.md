# Proxmox Golden Image — Packer

## One-time setup (per Proxmox host)

1. Create an API token: **Datacenter → Permissions → API Tokens → Add**.
   Give it a role with at least `VM.Clone`, `VM.Config.*`, `VM.Monitor`,
   `Datastore.AllocateSpace`. Never use the root account/password directly.
2. Import a cloud-init-ready base template once (see the prerequisite block
   at the top of `ubuntu-2404.pkr.hcl` for the exact commands). This gives
   Packer something to clone from — cloning is far faster and more reliable
   than scripting an unattended ISO install for every build.
3. Generate an SSH keypair if you don't already have one, and note the path.

## Build

```bash
cd image-pipeline/packer/proxmox
cp variables.pkrvars.hcl.example variables.pkrvars.hcl   # then fill in real values
packer init .
packer validate -var-file=variables.pkrvars.hcl ubuntu-2404.pkr.hcl
packer build   -var-file=variables.pkrvars.hcl ubuntu-2404.pkr.hcl
```

## What you get

A new Proxmox VM **template** named
`homelab-hardened-ubuntu-24-04-<timestamp>`. That naming convention is what
`infra/proxmox/main.tf` looks up later — "clone whatever is the newest
template matching `homelab-hardened-ubuntu-24-04-*`" — without this build
script and that Terraform ever needing to coordinate directly.

## Automating this on a schedule

See `.github/workflows/build-image-proxmox.yml` at the repo root for the
"check daily, build only if something changed" wrapper around this same
`packer build` command. That workflow needs a **self-hosted GitHub Actions
runner** with network access to your Proxmox host (a public GitHub-hosted
runner cannot reach a homelab by default) — running the small
`actions/runner` service on a machine on your own network is the standard
way to do this.
