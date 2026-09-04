# Atlantis — Self-Hosted PR-Gated Terraform

## Why this exists

In the enterprise pattern this repo models, nobody runs `terraform apply`
from a laptop against real infrastructure. Every change goes through a pull
request; a PR comment (`atlantis plan`, then `atlantis apply`) triggers
Terraform and posts the result back into the PR for review. This gives you
a reviewable diff, visible plan output before approval, and a durable audit
trail tied to Git history — recreating this, even solo, is genuinely useful
practice for the operational discipline, not just the Terraform syntax.

## Prerequisites

- A GitHub repository (can be this same repo, pushed to your own GitHub
  account) — Atlantis needs a real Git host webhook to trigger on PRs.
- A public URL Atlantis can be reached at. For a homelab experiment,
  [ngrok](https://ngrok.com/) (free tier) pointed at port 4141 is the
  fastest way to get this without exposing your home network directly.
- A GitHub Personal Access Token with `repo` scope.
- A webhook secret (any random string you generate yourself).

## Setup

1. Copy `.env.example` to `.env` and fill in real values (never commit `.env`).
2. Update `ATLANTIS_REPO_ALLOWLIST` in `docker-compose.yml` to your actual
   `github.com/<you>/<repo>`.
3. `docker compose up -d`
4. In your GitHub repo settings → Webhooks, add a webhook pointing at
   `<your-public-url>/events`, content type `application/json`, using the
   same secret as `ATLANTIS_GH_WEBHOOK_SECRET`.
5. Open a PR that changes a file under `infra/local`, `infra/proxmox`, or
   `infra/aws`. Atlantis should comment on the PR automatically with a plan.
6. Comment `atlantis apply` to apply it.

## Repo-level config

See `atlantis.yaml` at the repo root — it defines three separate Atlantis
"projects," one per target, each independently plannable/appliable. This
mirrors the real pattern's ~90 separate per-environment project directories,
just scaled down to 3.
