# Reusable Kubernetes application module.
#
# This module is deliberately provider-agnostic — it only talks to the
# standard `kubernetes` Terraform provider via whatever kubeconfig context
# is active. That means the EXACT SAME module works unmodified whether it's
# pointed at a local kind cluster, a homelab k3s cluster on Proxmox VMs, or
# a real Amazon EKS cluster. This is intentional: it proves that once you
# have "a Kubernetes API endpoint," the app-provisioning layer doesn't care
# how that cluster was built.

resource "kubernetes_deployment_v1" "app" {
  metadata {
    name      = var.app_name
    namespace = var.namespace
    labels    = { app = var.app_name }
  }

  spec {
    replicas = var.replica_count

    selector {
      match_labels = { app = var.app_name }
    }

    template {
      metadata {
        labels = { app = var.app_name }
      }

      spec {
        container {
          name  = var.app_name
          image = var.initial_image # only ever used on first create — see lifecycle block below

          port {
            container_port = var.container_port
          }

          resources {
            requests = {
              cpu    = var.cpu_request
              memory = var.memory_request
            }
            limits = {
              cpu    = var.cpu_limit
              memory = var.memory_limit
            }
          }

          readiness_probe {
            http_get {
              path = var.health_check_path
              port = var.container_port
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          liveness_probe {
            http_get {
              path = var.health_check_path
              port = var.container_port
            }
            initial_delay_seconds = 15
            period_seconds        = 20
          }
        }
      }
    }
  }

  # ============================================================
  # THIS is the load-bearing line in the entire repo.
  #
  # Without it, every `terraform plan` after a CI/CD deploy (which changes
  # the image via `kubectl set image`, NOT through Terraform) would show a
  # drift, because Terraform would still think `var.initial_image` is the
  # correct desired state. Eventually someone applies that "fix" and
  # accidentally rolls the app back to an old image. Ignoring this field is
  # what lets Terraform own the *shape* of the Deployment forever while the
  # CI/CD pipeline owns *what's actually running* — and neither one fights
  # the other for control.
  # ============================================================
  lifecycle {
    ignore_changes = [spec[0].template[0].spec[0].container[0].image]
  }
}

resource "kubernetes_service_v1" "app" {
  metadata {
    name      = var.app_name
    namespace = var.namespace
  }

  spec {
    selector = { app = var.app_name }

    port {
      port        = var.service_port
      target_port = var.container_port
      node_port   = var.service_type == "NodePort" ? var.node_port : null
    }

    type = var.service_type
  }
}

resource "kubernetes_horizontal_pod_autoscaler_v2" "app" {
  count = var.enable_autoscaling ? 1 : 0

  metadata {
    name      = var.app_name
    namespace = var.namespace
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment_v1.app.metadata[0].name
    }

    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = var.target_cpu_utilization
        }
      }
    }
  }
}
