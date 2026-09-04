output "deployment_name" {
  value = kubernetes_deployment_v1.app.metadata[0].name
}

output "service_name" {
  value = kubernetes_service_v1.app.metadata[0].name
}

output "current_image" {
  description = "Best-effort read of whatever image is live right now. Note: because of the ignore_changes lifecycle block, this may lag what's actually running if Terraform's state hasn't been refreshed since the last CI/CD deploy — use `kubectl get deployment` for ground truth."
  value       = kubernetes_deployment_v1.app.spec[0].template[0].spec[0].container[0].image
}
