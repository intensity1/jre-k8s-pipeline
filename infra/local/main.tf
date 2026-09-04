# Local target — points the standard `kubernetes` Terraform provider at a
# kind cluster's kubeconfig context.
#
# Note: Terraform does NOT create the kind cluster itself. This is
# deliberate and mirrors the real pattern: cluster/node lifecycle is treated
# as a separate concern from the Kubernetes-objects-on-top-of-it concern
# (in the enterprise version, EKS cluster creation and node group AMI
# lifecycle live in a different Terraform root than the app Deployment
# objects). Run `scripts/bootstrap-local.sh` (or `.ps1` on Windows) first,
# THEN run Terraform.

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "kind-homelab-pipeline"
}

module "sample_app" {
  source = "../modules/k8s-app"

  app_name       = "sample-app"
  namespace      = "default"
  initial_image  = var.initial_image
  container_port = 8080
  service_port   = 8080
  service_type   = "NodePort"
  node_port      = 30080

  # Small values appropriate for a laptop-sized kind cluster
  replica_count = 2
  min_replicas  = 2
  max_replicas  = 4
}
