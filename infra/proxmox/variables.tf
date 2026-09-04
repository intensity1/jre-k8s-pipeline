variable "proxmox_api_url" {
  type        = string
  description = "e.g. https://proxmox.homelab.local:8006/api2/json"
}

variable "proxmox_api_token" {
  type        = string
  sensitive   = true
  description = "format: user@realm!tokenid=secret"
}

variable "proxmox_node" {
  type = string
}

variable "snippet_storage" {
  type        = string
  default     = "local"
  description = "A Proxmox storage with 'Snippets' content type enabled"
}

variable "network_bridge" {
  type    = string
  default = "vmbr0"
}
