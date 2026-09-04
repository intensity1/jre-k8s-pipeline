variable "app_name" {
  type        = string
  description = "Name used for the Deployment, Service, and HPA"
}

variable "namespace" {
  type    = string
  default = "default"
}

variable "initial_image" {
  type        = string
  description = "Image used ONLY at first-create. After that, CI/CD owns this field via kubectl set image."
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "service_port" {
  type    = number
  default = 80
}

variable "service_type" {
  type    = string
  default = "ClusterIP"
}

variable "node_port" {
  type        = number
  default     = null
  description = "Only used when service_type = NodePort (e.g. for a local kind cluster with no cloud load balancer)"
}

variable "health_check_path" {
  type    = string
  default = "/healthz"
}

variable "replica_count" {
  type    = number
  default = 2
}

variable "cpu_request" {
  type    = string
  default = "100m"
}

variable "memory_request" {
  type    = string
  default = "128Mi"
}

variable "cpu_limit" {
  type    = string
  default = "250m"
}

variable "memory_limit" {
  type    = string
  default = "256Mi"
}

variable "enable_autoscaling" {
  type    = bool
  default = true
}

variable "min_replicas" {
  type    = number
  default = 2
}

variable "max_replicas" {
  type    = number
  default = 5
}

variable "target_cpu_utilization" {
  type    = number
  default = 70
}
