variable "initial_image" {
  type        = string
  default     = "ghcr.io/example/sample-app:bootstrap"
  description = "Placeholder image used only when the Deployment is first created. Push your own image (see apps/sample-app) and override this once, then let CI/CD take over from there."
}
