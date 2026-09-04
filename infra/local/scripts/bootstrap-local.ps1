# One-time (or any-time-you-want-a-fresh-cluster) bootstrap for the local
# target, Windows/PowerShell version. See bootstrap-local.sh for the
# rationale comment — cluster creation is intentionally kept OUT of
# Terraform here, mirroring the enterprise pattern this repo models.

if (-not (Get-Command kind -ErrorAction SilentlyContinue)) {
    Write-Error "kind is not installed. See https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
    exit 1
}
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Error "kubectl is not installed."
    exit 1
}

Set-Location (Join-Path $PSScriptRoot '..')

$existing = kind get clusters
if ($existing -contains 'homelab-pipeline') {
    Write-Output "kind cluster 'homelab-pipeline' already exists - skipping create."
} else {
    kind create cluster --config kind-config.yaml
}

kubectl cluster-info --context kind-homelab-pipeline
Write-Output "Cluster ready. Next: cd infra\local; terraform init; terraform apply"
