# Setup — Quickstart

Full reasoning lives in `../golden-image-and-app-deployment-pipeline-howto.md`.
This file is just the fastest path to something running.

## 1. Get the Kubernetes + CI/CD half working first (free, ~15 minutes)

```powershell
cd infra\local
.\scripts\bootstrap-local.ps1
terraform init
terraform apply
kubectl get deployment,svc,hpa -n default
curl http://localhost:8080/healthz
```

Push `apps/sample-app` to your own GitHub repo, set repo variable
`REGISTRY=ghcr.io/<your-username>`, and let
`.github/workflows/build-push-app.yml` +
`.github/workflows/deploy-app.yml` build and deploy it for real. Confirm a
change actually rolls out with:

```powershell
curl http://localhost:8080/version
```

...and watch the `git_sha` value change after each deploy.

## 2. Add the real image-build half (pick one)

Both paths run the same Ansible hardening playbook, which needs one collection
installed first:
```powershell
ansible-galaxy collection install -r image-pipeline\ansible\requirements.yml
```

### Proxmox path
```powershell
cd image-pipeline\packer\proxmox
copy variables.pkrvars.hcl.example variables.pkrvars.hcl
# fill in variables.pkrvars.hcl with your host details first
packer init .
packer build -var-file=variables.pkrvars.hcl ubuntu-2404.pkr.hcl

cd ..\..\..\infra\proxmox
# fill in terraform.tfvars first
terraform init
terraform apply
```

### AWS path
```powershell
cd image-pipeline\packer\aws
copy variables.pkrvars.hcl.example variables.pkrvars.hcl
packer init .
packer build -var-file=variables.pkrvars.hcl ubuntu-2404.pkr.hcl

cd ..\..\..\infra\aws
terraform init
terraform apply
```
Read `infra/aws/README.md` first — there's a known fidelity gap around the
base AMI that's worth understanding before you spend money running this.

## 3. Add PR-gated apply (Atlantis)

```powershell
cd atlantis
copy .env.example .env
# fill in .env, then:
docker compose up -d
```

See `atlantis/README.md` for the GitHub webhook wiring.

## 4. Add the change-management gate

Already wired: `deploy-app.yml`'s `workflow_dispatch` path for `prod`
requires an `approved_issue_number` input. Open an issue using the
`.github/ISSUE_TEMPLATE/production-deploy-request.md` template, get it
"approved" via comment, then reference its number when dispatching a prod
deploy.

## Reasonable order to actually learn this in

1. Local target end-to-end (prove the seam between Terraform-owns-shape and
   CI/CD-owns-image with your own eyes).
2. Proxmox OR AWS, whichever you have more comfortable access to, to add
   the real image-build half.
3. Atlantis, once you're tired of running `terraform apply` by hand.
4. The change-management gate, last — it's the thinnest layer and easiest
   to bolt on once everything else works.
