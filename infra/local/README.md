# Local Target (kind)

The only target in this repo you can run **right now, for free, with no
external account**. Use this to prove out the Kubernetes + CI/CD half of
the pattern before adding the real image-build half via Proxmox or AWS.

## Prerequisites

- Docker Desktop (or Docker Engine) running
- [`kind`](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- `kubectl`
- Terraform CLI

## Steps

```powershell
# 1. Create the kind cluster (NOT via Terraform - see the comment in main.tf)
.\scripts\bootstrap-local.ps1

# 2. Provision the app's Kubernetes objects
terraform init
terraform plan
terraform apply

# 3. Confirm it's up
kubectl get deployment,svc,hpa -n default
curl http://localhost:8080/healthz
```

## What's genuinely missing here vs. Proxmox/AWS

There is no real "golden image" step for this target — kind nodes are
containers, not VMs, so there's nothing to hardens/patch/replace at that
layer. The educational value of the `local` target is entirely in the
Kubernetes-object + CI/CD-deploy half of the pattern (Phases 6-9 of the main
how-to doc), not the image-build half (Phases 2-3). Move to `infra/proxmox`
or `infra/aws` once you want the full picture.

## Tearing down

```powershell
kind delete cluster --name homelab-pipeline
```
