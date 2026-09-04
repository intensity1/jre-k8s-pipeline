# Proxmox Target

Clones the newest hardened template (built by
`image-pipeline/packer/proxmox`) into a running VM, and bootstraps
single-node k3s on it via cloud-init.

## A genuine gap worth knowing about upfront

The `bpg/proxmox` Terraform provider does **not** have an AWS-style
`most_recent = true` data source. To replicate "look up the newest
template matching this name pattern," this folder ships a small Python
helper (`scripts/find_latest_template.py`) invoked via Terraform's `external`
data source. This is a legitimate, if slightly rougher, pattern — just be
aware it's a workaround for a provider gap, not a first-class Terraform
feature, and requires Python 3 + `pip install requests` on whatever machine
runs `terraform apply` (or Atlantis).

## Prerequisites

1. Build at least one image first: see `image-pipeline/packer/proxmox/README.md`.
2. An API token (same one Packer uses is fine, or a separate read-mostly
   one for Terraform).
3. Enable "Snippets" content type on a Proxmox storage (Datacenter →
   Storage → your storage → Content), so the k3s cloud-init file can be
   uploaded.
4. `pip install requests` in whatever environment runs Terraform.

## Apply

```bash
cp terraform.tfvars.example terraform.tfvars   # then fill in real values
export PROXMOX_API_URL="https://proxmox.homelab.local:8006/api2/json"
export PROXMOX_API_TOKEN="user@realm!tokenid=secret"
export PROXMOX_NODE="pve"
export PROXMOX_TEMPLATE_PREFIX="homelab-hardened-ubuntu-24-04-"

terraform init
terraform plan
terraform apply
```

## After apply — the manual step this repo is honest about

Terraform creates the VM and installs k3s via cloud-init, but fetching the
resulting kubeconfig off the VM is a **manual step**, not automated by
Terraform:

```bash
scp ubuntu@<vm-ip>:k3s.yaml ./kubeconfig-proxmox.yaml
export KUBECONFIG=./kubeconfig-proxmox.yaml
kubectl get nodes
```

This mirrors the real pattern this repo models: cluster bootstrap and
kubeconfig distribution are treated as a separate concern from the
Terraform module that provisions objects *on* the cluster (see
`infra/modules/k8s-app`). Once you have this kubeconfig, point
`infra/local`'s style of `provider "kubernetes"` block at it (swap
`config_context` for this cluster) to deploy the sample app here instead of
on kind.

## Node replacement (the actual "golden image" payoff)

To roll onto a newly built image: build a new template (re-run Packer),
then either bump `clone.vm_id` to the new template's ID manually, or —
since the data lookup is dynamic — simply re-run `terraform apply`, which
will pick up whatever the *newest* template is via the external data
source, and replace the VM. This is the direct homelab equivalent of the
enterprise "blue/green node swap, one node at a time" process.
