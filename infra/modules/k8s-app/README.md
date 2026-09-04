# k8s-app module

Provider-agnostic Terraform module that provisions a Kubernetes
Deployment + Service + optional HPA. Used identically by `infra/local`,
`infra/proxmox`, and `infra/aws` — only the `kubernetes` provider's
connection details differ between them, never this module.

## Usage

```hcl
module "sample_app" {
  source         = "../modules/k8s-app"
  app_name       = "sample-app"
  namespace      = "default"
  initial_image  = "ghcr.io/yourname/sample-app:bootstrap"
  container_port = 8080
}
```

## Why this module ignores the image field after creation

See the comment directly above the `lifecycle` block in `main.tf`, and
Phase 6 of the main how-to document. Short version: this module owns the
*shape* of the app. The CI/CD pipeline in `.github/workflows/deploy-app.yml`
owns *what's actually running*, via `kubectl set image`. The
`ignore_changes` block is what keeps those two owners from overwriting each
other.
