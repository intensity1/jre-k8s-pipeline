# Golden-Image + App-Deployment Pipeline — Starter Repo

A real, buildable implementation of the pattern described in
`docs/golden-image-and-app-deployment-pipeline-howto.md`. This repo is
deliberately organized so the **shared concepts** (hardening steps, the
Kubernetes app module, the CI/CD workflows) are written once, and only the
**target-specific infrastructure** differs between local / Proxmox / AWS.

## Status

Code has **not been executed or verified** in this environment (no Proxmox
host or AWS account is reachable here). Syntax and structure follow each
tool's documented conventions as of writing. Treat this as a strong,
correct-by-inspection starting point — run a `terraform validate` / `packer
validate` / `terraform plan` pass yourself before trusting it against real
infrastructure, per the standard practice this whole pattern is trying to
teach.

## Repo layout

```
image-pipeline/
  ansible/              hardening playbook — shared by Proxmox AND AWS builds
  packer/proxmox/        Packer template: clones a cloud-init base, hardens, re-templates
  packer/aws/             Packer template: builds a hardened Amazon EBS AMI
infra/
  modules/k8s-app/        reusable Terraform module (Deployment/Service/HPA) — provider-agnostic,
                           works against kind, k3s, or EKS identically. Contains the
                           lifecycle.ignore_changes line that is the whole point of this repo.
  local/                  kind cluster + this module — the only target you can run for free, today
  proxmox/                Terraform for cloning hardened templates into running VMs (bpg/proxmox)
  aws/                    Terraform using terraform-aws-modules/eks/aws — the de facto standard module
atlantis/                 self-hosted Atlantis (PR-gated terraform plan/apply), docker-compose based
apps/sample-app/          minimal Flask app: /healthz, /version (returns the git SHA baked at build)
.github/workflows/        image-build (Proxmox + AWS) and app build/deploy CI/CD
.github/ISSUE_TEMPLATE/   lightweight change-management analog for a "production deploy request"
atlantis.yaml             repo-level Atlantis project config (3 projects: local/proxmox/aws)
```

## Pick your starting target

| Target | Cost | What you need | Fidelity to a real datacenter |
|---|---|---|---|
| `infra/local` | Free | Docker + kind | Lowest — no VM layer, no real image build, but the K8s/CI/CD seam is identical |
| `infra/proxmox` | Free (your hardware) | A Proxmox VE host + API token | High — real VM images, real hardening, real node replacement |
| `infra/aws` | ~$/hr while running | An AWS account | Highest — real managed EKS, real AMI pipeline, closest to production |

Start with `infra/local` to prove the Kubernetes/CI/CD half of the pattern
works, then move to Proxmox or AWS to add the real image-build half. See each
subfolder's own `README.md` for exact steps.

## The one line that matters most

In `infra/modules/k8s-app/main.tf`:

```hcl
lifecycle {
  ignore_changes = [spec[0].template[0].spec[0].container[0].image]
}
```

This is what makes Terraform and the CI/CD pipeline stop fighting over the
image field. Everything else in this repo exists to support that one
architectural decision. See the main how-to doc, Phase 6, for the full
justification.
