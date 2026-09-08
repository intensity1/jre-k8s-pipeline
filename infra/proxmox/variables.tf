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

variable "ssh_private_key_path" {
  type        = string
  description = "Path to a private key authorized for root SSH on the Proxmox node itself. Required by the bpg/proxmox provider for file-upload operations (e.g. the k3s snippet) — these go over SSH, not the REST API. Must be an absolute path; Terraform's file() does not expand '~'."
}

variable "ssh_public_key_path" {
  type        = string
  description = "Public key injected via cloud-init into the 'ubuntu' user's authorized_keys on every cloned node — without this, cloned VMs have no way to log in at all (the golden image itself has no baked-in key by design). Must be an absolute path."
}
