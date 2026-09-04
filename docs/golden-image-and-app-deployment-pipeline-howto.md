# How to Build Your Own Golden-Image + App-Deployment Pipeline

A portable, from-scratch guide to recreating a production-grade "immutable golden image + independent app deployment" architecture — in a Proxmox homelab, in a personal AWS account, or fully local. This document generalizes a real, working enterprise pattern with all identifying detail removed. It is written so any engineer, with no prior context, could execute it end to end.

---

## 0. The mental model (read this before anything else)

Everything below is one architecture built from **two pipelines that are deliberately independent and never talk to each other directly**:

```
PIPELINE A — IMAGE BUILD                    PIPELINE B — APP DEPLOYMENT
(runs on a clock, nobody watches it)        (runs on a human/CI event)

Upstream OS vendor publishes a new     ┐
base image                             │
        ↓                              │        Developer pushes code
Your build automation notices,         │                ↓
hardens it (config mgmt), bakes in     │        CI builds a container image,
your security agent(s)                 │        tags it, pushes to a registry
        ↓                              │                ↓
Finished image lands in your own       │        CD patches the *already running*
image store, named with a version-     │        Kubernetes Deployment's image
aware convention                       │        field directly (no infra changes)
        ↓                              ┘                ↓
        .                                       Rollout is verified; rollback
        .  (no connection except naming)        available on failure
        ↓                                              ↓
Terraform/IaC looks up "the newest                Environments are promoted by
image matching X" ONLY when a human               re-running the *same pipeline*
runs it against a specific cluster/node            against a different branch —
group — never automatically                        not by moving one image forward
```

**Why this split exists (the justification you'll want to explain to anyone you show this to):**

1. **Blast radius separation.** A bad OS/kernel patch and a bad app release are two completely different failure modes. If they're coupled, you can never tell which one caused an incident, and you can't roll one back without touching the other.
2. **Different owners, different cadences.** Infra/platform teams own the machine; app teams own the code. Coupling them creates a permission and approval nightmare — every app deploy would need infra sign-off, or every OS patch would need app teams to re-test.
3. **Immutability wins on the machine side.** You never patch a running node in place. You build a new image and replace the node. This eliminates configuration drift entirely — every node is provably identical to its image, forever.
4. **Mutability wins on the app side.** Containers change constantly (many times a day). Rebuilding a full VM image per code change would be far too slow. A container image push + an imperative "update the running pod's image" is fast and cheap.

If you remember one sentence: **the machine is replaced, never patched; the app is updated, never rebuilt into the machine.**

---

## 1. Component equivalency table

Use this to swap in whatever you have access to. None of the specific product choices matter — the *shape* of the pipeline is what makes this work.

| Role in the pipeline | Enterprise-grade example | Proxmox homelab equivalent | Personal AWS equivalent |
|---|---|---|---|
| Base OS image source | Cloud vendor's published AMI/image catalog | Official Debian/Ubuntu/Rocky cloud-init `.qcow2` images | AWS-owned public AMIs (Amazon Linux, Ubuntu) |
| Image build/hardening engine | Cloud-native image builder service + config management | **Packer** (Proxmox builder plugin) + **Ansible** | AWS Image Builder, or Packer against AWS too — both work |
| Config management / hardening steps | Ansible playbook (CIS-style hardening, agent install) | Same — Ansible playbook, generalized security baseline | Same |
| Security agent baked into image | Commercial EDR agent | **Wazuh agent** or **osquery** (free, real EDR-style telemetry) | Same, or AWS-native GuardDuty agent |
| Finished image store | Cloud-native native image storage (AMI store) | Proxmox VM **templates** (or a local image registry) | AWS AMI (same account) |
| Build trigger/schedule | CI runner on a daily cron | GitHub Actions (free tier) with a cron trigger, **or** a systemd timer / cron job on a local runner | GitHub Actions, same |
| "What changed since yesterday" check | A committed JSON file diffed against a live API query | Same pattern — commit `latest-image.json`, diff against a live query each run | Same |
| Infra-as-code | Terraform, modules per resource type | **Terraform** (unchanged — this tool doesn't need substituting) | Terraform |
| PR-gated apply automation | Self-hosted PR-triggered Terraform runner | **Atlantis**, self-hosted via Docker Compose (free, real thing) | Atlantis in a container, or Terraform Cloud free tier |
| Kubernetes runtime | Managed Kubernetes service, node groups | **k3s** (lightweight, ideal for homelab) or **kind** for pure local | Amazon EKS (small/cheap: 1 managed node group, `t3.small`) |
| Container registry | Enterprise artifact repository | **A local Docker registry** (`registry:2` container) or GitHub Container Registry (GHCR, free) | Amazon ECR (cheap, generous free tier) |
| App CI/CD engine | GitHub Actions, reusable workflows | GitHub Actions — same tool works unmodified here | GitHub Actions |
| Image deploy mechanism | `kubectl set image` against a live Deployment | Same — unchanged, `kubectl` works identically everywhere | Same |
| Change management / approval gate | Enterprise ITSM ticketing (multi-approver workflow) | A **GitHub Issue template** with a manual "approved" label, or just a required PR review | A GitHub Issue, or AWS Systems Manager Change Manager (real free-tier service) |

**Justification for the free/homelab substitutions**: every one of them is a genuine, widely-used, production-credible tool — this isn't a "toy" version of the pattern. Wazuh, Atlantis, k3s, and GHCR are all used in real production environments. You are not learning a simplified imitation; you're learning the identical shape with different brand names underneath.

---

## 2. Prerequisites

Pick **one** target and get it working end-to-end before trying the others. Recommended order: **Proxmox first** (cheapest, most instructive, no cloud bill), **AWS second** (validates the exact same pattern against real managed services), **pure local last** (fastest iteration once you understand it).

### Common to all targets
- Git + a GitHub account (free tier is enough — Actions minutes, GHCR storage)
- Terraform CLI (`>= 1.7`)
- `kubectl`
- Docker or Podman (for building containers, running Atlantis, running a local registry)
- Ansible, plus the `community.general` collection (`ansible-galaxy collection install community.general`) for the firewall hardening tasks

### Proxmox-specific
- A Proxmox VE host (a single node is fine — this doesn't need a cluster)
- An API token for Proxmox (Datacenter → Permissions → API Tokens) — never use your root password in automation
- Packer with the `hashicorp/proxmox` plugin

### AWS-specific
- A personal AWS account with billing alerts configured (this pattern is cheap but not free — budget ~$30-60/mo if you keep it running, far less if you tear it down between sessions)
- An IAM user or role scoped to only what's needed (EC2, EKS, ECR, Image Builder, IAM-for-those-services) — do not use root credentials
- `aws` CLI configured with a named profile

---

## 3. Phase-by-phase build guide

### Phase 1 — Decide your base image and naming convention

Before writing any automation, decide the naming pattern your finished images will carry. This single decision is what lets the "consume" side (Terraform) find the right image later without any direct coordination with the "build" side. This is the load-bearing convention of the entire system.

**Example convention**: `homelab-hardened-<os>-<version>-<build-timestamp>`
e.g. `homelab-hardened-ubuntu-24.04-2026-08-06T0100`

Justification: the consuming side will do a "most recent image matching `homelab-hardened-ubuntu-24.04-*`" lookup. If the name doesn't embed the OS version, you can't scope a lookup to a specific version — you'd always get the newest image regardless of version, which breaks the ability to run multiple K8s/OS versions side by side.

### Phase 2 — Build the image-hardening definition (Packer + Ansible)

Directory layout:
```
image-pipeline/
  packer/
    ubuntu-24-04.pkr.hcl              # source + build block
    variables.pkrvars.hcl.example     # copy to variables.pkrvars.hcl before use
  ansible/
    hardening.yml              # the playbook — CIS-style baseline + agent install
    roles/
      baseline-hardening/
      security-agent/
```

**A naming gotcha worth knowing before you copy this structure**: the vars file must use the `.pkrvars.hcl` extension, never `.pkr.hcl`. Packer auto-loads every `*.pkr.hcl` file in a directory as part of the build template whenever you run `packer init`/`packer build`/`packer validate` there — even against a single named file, it still loads the whole parent directory. A vars file's bare `key = value` lines aren't valid inside a template file (only `variable`/`source`/`build`/`packer`/`data` blocks are), so naming it `variables.pkr.hcl` breaks every Packer command run in that folder. This is an easy mistake to copy from someone else's example — worth double-checking the extension every time.

Minimal `packer` build block (Proxmox target) — the actual values you'll fill in are homelab-specific, but the **shape** is what matters:

```hcl
source "proxmox-iso" "hardened_ubuntu" {
  # ... connection + ISO/template details ...
}

build {
  sources = ["source.proxmox-iso.hardened_ubuntu"]

  provisioner "ansible" {
    playbook_file = "../ansible/hardening.yml"
  }
}
```

The Ansible playbook is where the "hardening steps" enterprise pattern lives — this is the direct equivalent of the 29KB `components.tf`-style hardening definitions in the enterprise version. Concretely, your playbook should do at minimum:
1. OS patching to current (`apt upgrade` / `dnf upgrade`)
2. Disable password auth over SSH, enforce key-based only
3. Install and enable your security agent (Wazuh/osquery)
4. Apply a baseline firewall policy (ufw/firewalld defaults)
5. Tag the resulting image with a build-time metadata (OS version, build date, playbook git SHA) — this is your audit trail

**Justification**: baking the agent in at build time (not after boot) guarantees every instance that ever runs is provably covered by security tooling from the first second it exists — there is no window where a fresh instance is unmonitored.

### Phase 3 — Automate the "check daily, build only if needed" logic

This is the piece that makes the pipeline efficient instead of wasteful. Do not skip this — building on every single trigger is the single most common mistake when people try to recreate this pattern, and it burns compute/time for no benefit.

GitHub Actions workflow, conceptually:

```yaml
name: build-hardened-image
on:
  workflow_dispatch:
  schedule:
    - cron: '0 1 * * *'   # daily, adjust to your timezone needs

jobs:
  check-and-build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Query upstream for the newest base image
        id: upstream
        run: |
          # Proxmox: check the published cloud-image checksum/date file
          # AWS: aws ec2 describe-images --owners <vendor> --filters ...
          echo "latest=$(...)" >> "$GITHUB_OUTPUT"

      - name: Compare against last known
        id: diff
        run: |
          last=$(cat latest-known.json | jq -r .id)
          if [ "$last" == "${{ steps.upstream.outputs.latest }}" ]; then
            echo "changed=false" >> "$GITHUB_OUTPUT"
          else
            echo "changed=true" >> "$GITHUB_OUTPUT"
          fi

      - name: Run Packer build
        if: steps.diff.outputs.changed == 'true'
        run: packer build image-pipeline/packer/ubuntu-24-04.pkr.hcl

      - name: Update tracking file + open PR
        if: steps.diff.outputs.changed == 'true'
        run: |
          # write new value to latest-known.json, commit, open a PR, auto-merge
```

**Justification for each piece:**
- `workflow_dispatch` + `schedule` together: lets you force a manual run for testing without waiting for the cron, exactly like the enterprise version.
- The committed `latest-known.json` file, rather than an in-memory or database check, means your "have we already built this" state is version-controlled, auditable, and survives runner restarts for free.
- Gating the actual (expensive, slow) build behind a cheap comparison check is what turns this from "builds every day" into "checks every day, builds rarely" — a large efficiency and cost win at scale, and the exact same reasoning applies even in a homelab where your build might take 20+ minutes.

### Phase 4 — Provision Kubernetes and wire Terraform to *look up* the image (not own it)

This is the most important structural decision in the entire system, so read this phase twice.

```hcl
data "local_file" "latest_image_meta" {
  # or: data source hitting Proxmox/AWS API for "most recent template matching name pattern"
  filename = "latest-known.json"
}

resource "proxmox_vm_qemu" "eks_node" {   # or aws_instance / EKS node group launch template
  clone = jsondecode(data.local_file.latest_image_meta.content).template_name
  # ...
}
```

**Justification**: Terraform's job here is to look up "the current newest image matching this naming pattern" **at the moment someone runs `terraform apply`**, not to be notified when a new image appears. This is deliberate: it means image *builds* never force an unplanned infrastructure change. A human (or a scheduled maintenance job) has to decide, separately, "now is the time to roll nodes onto the new image." Nothing bridges those two decisions automatically. If you want the connection between build and adopt to ever become automatic, that is a conscious, later decision — not a default.

### Phase 5 — Set up PR-gated apply automation (Atlantis)

Self-host Atlantis via Docker Compose against your own Git repo (public or a private one you control):

```yaml
# atlantis.yaml (repo config)
version: 3
projects:
  - name: k8s-nodes
    dir: terraform/nodes
    workflow: default
```

**Justification**: the reason production systems use a PR-gated apply tool instead of someone running `terraform apply` from a laptop is threefold — (1) every change has a reviewable diff before it's applied, (2) the plan output is visible to reviewers before approval, and (3) there's a durable audit trail of who approved what and when, tied to a Git history. Recreating this step, even solo, teaches you the actual operational discipline — you'll comment `atlantis plan` / `atlantis apply` on your own PRs instead of running Terraform locally.

### Phase 6 — Build the app deployment pipeline, and make Terraform ignore the image field

In your Kubernetes-object Terraform module:

```hcl
resource "kubernetes_deployment_v1" "app" {
  lifecycle {
    ignore_changes = [spec[0].template[0].spec[0].container[0].image]
  }
  spec {
    template {
      spec {
        container {
          image = var.initial_image   # only used on first-create
        }
      }
    }
  }
}
```

**Justification**: this single line is what prevents Terraform and your CI/CD pipeline from fighting over who owns the image field. Without it, every `terraform plan` after a deploy would show a "drift" (because the CI/CD pipeline changed the image out from under Terraform), and eventually someone would `terraform apply` and accidentally roll the app back to whatever old image Terraform still thinks is correct. This is a real, commonly-hit mistake — build this in from day one rather than discovering it the hard way.

### Phase 7 — CI: build and push the app image

```yaml
# .github/workflows/build-push.yaml
- name: Build and push
  run: |
    docker build -t $REGISTRY/$IMAGE:$(git rev-parse --short HEAD) .
    docker push $REGISTRY/$IMAGE:$(git rev-parse --short HEAD)
```

**Justification for tagging by git SHA**: this ties every running image back to an exact, reproducible commit — there's never ambiguity about "which version of the code is this." It also naturally supports a **skip-if-already-built** optimization: check the registry for the tag before building; if it exists, skip straight to deploy.

### Phase 8 — CD: patch the running Deployment directly

```yaml
# .github/workflows/deploy.yaml
- name: Deploy new image
  run: |
    kubectl set image deployment/$APP_NAME $CONTAINER=$REGISTRY/$IMAGE:$TAG -n $NAMESPACE
    kubectl rollout status deployment/$APP_NAME -n $NAMESPACE --timeout=5m
```

Add real diagnostics on failure — this is a place enterprises spend real engineering effort and it's worth copying directly:

```yaml
- name: Diagnose failure
  if: failure()
  run: |
    kubectl describe deployment/$APP_NAME -n $NAMESPACE
    kubectl get pods -n $NAMESPACE -l app=$APP_NAME
    kubectl logs -n $NAMESPACE -l app=$APP_NAME --previous --tail=100
```

**Justification**: `kubectl set image` is intentionally the *only* thing that changes at deploy time. It's a single, narrow, auditable operation — much easier to reason about than "re-apply the whole manifest," which risks unintentionally changing replica counts, resource limits, or other fields that should stay stable between deploys.

### Phase 9 — Environment promotion: branch-per-environment, not image-per-environment

Model each environment as its own branch with its own auto-deploy trigger:

```yaml
on:
  push:
    branches: [dev]        # auto-deploys to dev only
  workflow_dispatch:        # prod requires a manual trigger
```

**Justification**: this deliberately avoids "promote a tested image forward" in favor of "rebuild fresh at each stage." The tradeoff is honest: you get a fresh, from-source build validated at every environment (a rebuild-time regression is caught early), at the cost of technically not testing the *exact same binary* all the way to prod. This is a real, debatable design choice — some organizations promote a single artifact instead. If you want to explore the alternative, that's a legitimate architecture decision to research separately; this doc describes the rebuild-per-environment model because that's the pattern being recreated.

### Phase 10 — A lightweight change-management analog

You don't need a full ITSM system to get the educational value of a gated production deploy. Use a GitHub Issue template:

```markdown
## Production Deploy Request
- App: 
- Git SHA: 
- Risk: Low / Medium / High
- Rollback plan: 
- Approved by: (comment "approved" to proceed)
```

Wire your prod deploy workflow to require a `workflow_dispatch` input referencing an approved issue number, and — optionally — a required PR review as an actual enforced gate (`branch protection rules`).

**Justification**: the point isn't to imitate enterprise ITSM tooling exactly — it's to practice the *discipline* of "prod changes require a documented reason, a rollback plan, and a recorded approval," which is the real value of that process regardless of what system enforces it.

---

## 4. Filling in the two gaps this pattern is known to have (build these in from day one)

Recreating this pattern is also a chance to fix two weaknesses that are easy to miss the first time around:

1. **Build-failure alerting.** A scheduled build that silently fails is worse than no automation at all, because it creates false confidence. Add a final step to your build workflow that posts to a webhook (Slack, Discord, ntfy.sh — all free) on failure. Do not skip this "boring" step; it's the difference between a pipeline you can trust unattended and one you have to babysit.
2. **Drift detection.** Since Atlantis only reacts to PRs, nothing catches someone changing a resource out-of-band (e.g., editing something directly in Proxmox or the AWS console). Add a *separate*, read-only scheduled `terraform plan` (no apply) that alerts if it detects any diff. This is a cheap, high-value addition many real implementations skip.

---

## 5. MVP path vs. full-fidelity path

If this is your first time building this, don't try to do all 10 phases at once. Suggested order:

**MVP (weekend project):**
1. Phase 2 + 3 manually triggered only (skip the daily cron at first) — get one hardened image built successfully.
2. Phase 4, applied by hand (`terraform apply` locally is fine for now) — get one node running from that image.
3. Phase 6 + 7 + 8 — get one app deployed and updated via `kubectl set image`, by hand.

**Full-fidelity (once the MVP works):**
4. Add the daily schedule + diff-check (Phase 3 properly).
5. Add Atlantis (Phase 5) so you stop running `terraform apply` locally.
6. Add branch-per-environment CI/CD (Phase 9).
7. Add the change-management analog and the two gap-fills (Phase 10 + Section 4).

---

## 6. Proxmox hardware sizing (rough guidance)

This entire pattern is light enough to run on very modest homelab hardware:
- **CPU**: 4+ cores free for k3s + Atlantis + a build VM (Packer builds are the heaviest transient load)
- **RAM**: 16GB minimum, 32GB comfortable (k3s: ~2-4GB, Atlantis: <1GB, a build VM during Packer runs: 2-4GB transient)
- **Storage**: 100GB+ free, since every image build produces a new template until you prune old ones

---

## 7. What this document does *not* cover (be honest about the gaps)

Reiterating per your request — here's what I'd flag as **not yet enough** if you want full fidelity to the enterprise pattern this was generalized from:

- **Multi-cluster/multi-account isolation** — the real pattern separates build and consume across account/network boundaries for blast-radius reasons. A single-Proxmox-host or single-AWS-account homelab collapses that boundary; worth calling out to anyone you hand this to, so they know it's a simplification, not an oversight.
- **Actual working code** — this document was originally written as a *design and reasoning* guide with representative snippets, not copy-paste-ready files. **Update: a complete, working starter repo now exists** in this same repo (repo root) — real `.pkr.hcl` templates, real Terraform modules (local/Proxmox/AWS), real GitHub Actions workflow YAML, a sample Flask app, and an Atlantis setup. See the repo-root `README.md` and `SETUP.md` for the fastest path to something running. It has not been executed against real infrastructure in this environment (no Proxmox host or AWS account reachable here) — validate it yourself (`terraform validate`, `packer validate`) before trusting it against real infra, same as any code you'd copy from elsewhere.
- **Secrets management** — this doc doesn't cover how to handle Proxmox/AWS credentials, registry auth, or webhook URLs safely (e.g., `sops`, `age`, GitHub Actions encrypted secrets, Vault). Worth its own short doc before you wire real credentials into any of this.
- **Networking specifics** — VPC/subnet design (AWS) or vSwitch/VLAN design (Proxmox) aren't covered; this doc assumes you already have basic connectivity between your build tooling and your targets.

If any of those matter to you, that's where to go deep next — the starter repo already covers the "actual working code" gap above; multi-cluster isolation, secrets management, and networking specifics remain open if you want to take this further.
