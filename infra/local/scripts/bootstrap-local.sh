#!/usr/bin/env bash
set -euo pipefail

# One-time (or any-time-you-want-a-fresh-cluster) bootstrap for the local
# target. This stands in for "provision the EKS cluster" / "provision the
# Proxmox VMs running k3s" in the other two targets — cluster creation is
# intentionally kept OUT of Terraform here, same as it is in the enterprise
# pattern this repo is modeling.

command -v kind >/dev/null 2>&1 || { echo "kind is not installed. See https://kind.sigs.k8s.io/docs/user/quick-start/#installation"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is not installed."; exit 1; }

cd "$(dirname "$0")/.."

if kind get clusters | grep -q '^homelab-pipeline$'; then
  echo "kind cluster 'homelab-pipeline' already exists — skipping create."
else
  kind create cluster --config kind-config.yaml
fi

kubectl cluster-info --context kind-homelab-pipeline
echo "Cluster ready. Next: cd infra/local && terraform init && terraform apply"
