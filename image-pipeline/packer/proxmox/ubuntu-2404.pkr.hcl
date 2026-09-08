# Packer template: builds a hardened Ubuntu 24.04 image on Proxmox VE.
#
# Uses the `proxmox-clone` builder (packer-plugin-proxmox — the standard,
# HashiCorp-maintained Packer plugin for Proxmox). This clones an EXISTING
# cloud-init-ready template rather than booting from an ISO. Cloning is the
# common real-world pattern because it avoids scripting an unattended OS
# installer (autoinstall/preseed) for every build — you do that install
# once, by hand or with a small setup script, and Packer only has to clone +
# harden + re-template from then on.
#
# ONE-TIME PREREQUISITE (do this once per Proxmox host, not per build):
#   Import a cloud image as a base template so Packer has something to clone:
#     wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
#     qm create 9000 --name ubuntu-2404-cloudinit-base --memory 2048 --net0 virtio,bridge=vmbr0
#     qm importdisk 9000 noble-server-cloudimg-amd64.img local-lvm
#     qm set 9000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9000-disk-0
#     qm set 9000 --ide2 local-lvm:cloudinit
#     qm set 9000 --boot c --bootdisk scsi0
#     qm set 9000 --serial0 socket --vga serial0
#     qm template 9000
#
# This template's ID (9000 above) is what `clone_vmid` below refers to.

packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.8"
      source  = "github.com/hashicorp/proxmox"
    }
    ansible = {
      version = ">= 1.1.1"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

variable "proxmox_api_url" {
  type        = string
  description = "e.g. https://proxmox.homelab.local:8006/api2/json"
}

variable "proxmox_api_token_id" {
  type        = string
  description = "e.g. packer@pve!packer-token — create via Datacenter > Permissions > API Tokens. Never use the root password here."
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  type      = string
  sensitive = true
}

variable "proxmox_node" {
  type        = string
  description = "The Proxmox node name to build on"
}

variable "clone_vmid" {
  type        = number
  description = "VMID of the pre-existing cloud-init base template (see prerequisite above)"
  default     = 9000
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

locals {
  # This naming convention is the load-bearing decision described in the
  # main how-to doc, Phase 1: it lets Terraform later look up "the newest
  # image matching homelab-hardened-ubuntu-24-04-*" without any direct
  # coordination with this build pipeline.
  build_timestamp = formatdate("YYYY-MM-DD'T'hhmm", timestamp())
  image_name       = "homelab-hardened-ubuntu-24-04-${local.build_timestamp}"
}

source "proxmox-clone" "hardened_ubuntu" {
  proxmox_url              = var.proxmox_api_url
  username                  = var.proxmox_api_token_id
  token                     = var.proxmox_api_token_secret
  insecure_skip_tls_verify  = true # set false once you have a real cert

  node         = var.proxmox_node
  clone_vm_id  = var.clone_vmid
  vm_name      = local.image_name
  full_clone   = true

  cores    = 2
  memory   = 2048
  scsi_controller = "virtio-scsi-pci"

  cloud_init              = true
  cloud_init_storage_pool = "local-lvm"

  # Required so Packer can actually discover this VM's DHCP-assigned IP via
  # the Proxmox API's guest-agent channel. Without this, Packer has no way
  # to find the IP at all and will sit at "Waiting for SSH" until it times
  # out, even if the VM boots and networks itself perfectly fine — this was
  # the missing piece the first build hit. Ubuntu's official cloud images
  # ship qemu-guest-agent pre-installed and enabled, so the guest side is
  # already covered once the VM config (set on the base template) turns the
  # agent channel on.
  qemu_agent = true

  ssh_username         = "ubuntu"
  ssh_private_key_file = replace(var.ssh_public_key_path, ".pub", "")
  ssh_timeout          = "10m"

  # After provisioning, convert the resulting VM into a new template —
  # this IS the finished, hardened golden image other Terraform will clone.
  template_name        = local.image_name
  template_description = "Hardened Ubuntu 24.04, built ${local.build_timestamp}"
}

build {
  sources = ["source.proxmox-clone.hardened_ubuntu"]

  provisioner "ansible" {
    playbook_file = "../../ansible/hardening.yml"
    # Without this, the plugin's proxy-adapter mode generates an inventory
    # using the LOCAL control machine's OS username instead of the actual
    # remote account (ssh_username above) — confirmed by inspecting the
    # generated inventory directly: it showed "ansible_user=homenest" (a
    # WSL-local user that doesn't exist on the VM at all) instead of
    # "ubuntu". That silently-wrong user is what broke every remote path
    # Ansible tried to construct, surfacing as a confusing "No space left
    # on device" on a tiny mkdir rather than a clear auth/user error.
    user = "ubuntu"
    extra_arguments = [
      "--extra-vars", "image_build_date=${local.build_timestamp}"
    ]
  }

  post-processor "shell-local" {
    inline = [
      "echo Built and templated: ${local.image_name}"
    ]
  }
}
