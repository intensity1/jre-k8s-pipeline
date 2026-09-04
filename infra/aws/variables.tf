variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "initial_image" {
  type        = string
  default     = "ghcr.io/example/sample-app:bootstrap"
  description = "Placeholder image used only when the Deployment is first created."
}
