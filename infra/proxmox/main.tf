# Proxmox target — clones the newest hardened template built by
# image-pipeline/packer/proxmox, boots it as a real VM, and installs
# single-node k3s via cloud-init so Kubernetes has something to run on.
#
# Provider choice: bpg/proxmox (terraform-provider-proxmox by bpg) rather
# than the older Telmate/proxmox provider. bpg/proxmox is the actively
# maintained, more modern option as of this writing and is the one
# generally recommended in current Proxmox+Terraform community guidance —
# Telmate's is still widely used but has a much slower release cadence.

terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = var.proxmox_api_token
  insecure  = true # homelab self-signed cert; set false with a real cert

  # Required for proxmox_virtual_environment_file: uploading content
  # (like the k3s snippet below) goes over SSH to the node directly, not
  # through the REST API — the bpg/proxmox provider's own design, not
  # something the Proxmox API itself is missing.
  ssh {
    agent       = false
    username    = "root"
    private_key = file(var.ssh_private_key_path)
  }
}

# Replicates AWS's `most_recent = true` AMI lookup, since the Proxmox
# provider has no native equivalent data source. See scripts/README for
# how this works.
data "external" "latest_template" {
  program = ["python3", "${path.module}/scripts/find_latest_template.py"]

  query = {
    # `query` values aren't used by the script (env vars are), but the
    # external provider requires this attribute to be present.
    trigger = "lookup"
  }
}

# Uploads the k3s bootstrap cloud-init snippet so the VM can reference it.
# Requires a storage backend with "Snippets" content enabled (Datacenter ->
# Storage -> <your storage> -> Content -> check "Snippets").
resource "proxmox_virtual_environment_file" "k3s_userdata" {
  content_type = "snippets"
  datastore_id = var.snippet_storage
  node_name    = var.proxmox_node

  source_raw {
    data      = file("${path.module}/cloud-init/k3s-user-data.yaml")
    file_name = "k3s-user-data.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "k8s_node" {
  name      = "homelab-k8s-node-01"
  node_name = var.proxmox_node

  clone {
    vm_id = tonumber(data.external.latest_template.result.vmid)
    full  = true
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 4096
  }

  # Tells Terraform to actually wait for and query the QEMU guest agent
  # (baked into the golden image — see docs/packer-explained.md) rather
  # than just hoping it's there. This is what makes ipv4_addresses below a
  # real value instead of an empty list: without it, apply can finish
  # before the agent's ever been asked.
  agent {
    enabled = true
  }

  initialization {
    # Without this, cloned nodes have no way to log in at all — the golden
    # image deliberately has no baked-in key (see docs/packer-explained.md),
    # so each clone needs one injected fresh via cloud-init at boot.
    user_account {
      username = "ubuntu"
      keys     = [trimspace(file(var.ssh_public_key_path))]
    }

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
    user_data_file_id = proxmox_virtual_environment_file.k3s_userdata.id
  }

  network_device {
    bridge = var.network_bridge
  }
}

output "cloned_from_template" {
  value = data.external.latest_template.result.name
}

output "node_ip" {
  description = "The k3s node's LAN IP, read via the QEMU guest agent — no console/ARP-sweep needed now that the golden image has the agent baked in."
  # index [0] is always loopback (127.0.0.1); index [1] is the first
  # (and here, only) network_device. try() avoids an error on the first
  # apply of a brand-new VM, before the agent has reported in yet.
  value = try(proxmox_virtual_environment_vm.k8s_node.ipv4_addresses[1][0], "not yet reported — re-run 'terraform apply' or 'terraform refresh' once the VM has booted")
}

output "fetch_kubeconfig_cmd" {
  description = "Copy-pasteable command to pull the kubeconfig off the node."
  value       = "scp -i ~/.ssh/homelab_pipeline_key ubuntu@${try(proxmox_virtual_environment_vm.k8s_node.ipv4_addresses[1][0], "<ip-not-yet-known>")}:k3s.yaml ./kubeconfig-proxmox.yaml"
}
