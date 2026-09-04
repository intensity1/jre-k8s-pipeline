# Sample App

A deliberately minimal Flask app used to exercise the full CI/CD half of
this pipeline. It exists to be deployed, not to be interesting.

- `GET /` — hello world + the git SHA it was built from
- `GET /healthz` — used by Kubernetes readiness/liveness probes
- `GET /version` — just the git SHA, useful for confirming a deploy landed

## Local test

```bash
docker build --build-arg GIT_SHA=$(git rev-parse --short HEAD) -t sample-app:local .
docker run -p 8080:8080 sample-app:local
curl http://localhost:8080/version
```

## How it gets deployed

See `.github/workflows/build-push-app.yml` (builds + pushes, tag = short
git SHA) and `.github/workflows/deploy-app.yml` (runs `kubectl set image`
against whichever cluster's kubeconfig is configured for that environment).
Both workflows currently hardcode `apps/sample-app` as the build context and
`sample-app` as the image/app name — copy this folder as a template for a
second app, then update those hardcoded values (or parameterize them as
workflow inputs) in your copy of the workflows.
