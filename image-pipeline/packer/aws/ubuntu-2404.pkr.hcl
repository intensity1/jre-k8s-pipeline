# Packer template: builds a hardened Ubuntu 24.04 AMI on AWS.
#
# Uses the `amazon-ebs` builder — the standard, most widely used Packer
# builder for AWS AMIs. Boots a temporary EC2 instance from Canonical's
# published base AMI, runs the SAME Ansible hardening playbook used for the
# Proxmox build, then snapshots the result into a new AMI.

packer {
  required_plugins {
    amazon = {
      version = ">= 1.3.0"
      source  = "github.com/hashicorp/amazon"
    }
    ansible = {
      version = ">= 1.1.1"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  type    = string
  default = "t3.micro" # cheap, sufficient for a build instance
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

locals {
  build_timestamp = formatdate("YYYY-MM-DD'T'hhmm", timestamp())
  image_name       = "homelab-hardened-ubuntu-24-04-${local.build_timestamp}"
}

# Canonical's own published Ubuntu 24.04 (Noble) AMI — always resolves to
# the current newest one at build time, same "ask the vendor what's newest"
# pattern used by the enterprise version of this pipeline.
source "amazon-ebs" "hardened_ubuntu" {
  region        = var.aws_region
  instance_type = var.instance_type
  ssh_username  = "ubuntu"

  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["099720109477"] # Canonical's official AWS account
    most_recent = true
  }

  ami_name        = local.image_name
  ami_description = "Hardened Ubuntu 24.04, built ${local.build_timestamp}"

  tags = {
    Name        = local.image_name
    BuildDate   = local.build_timestamp
    Hardened    = "true"
    BuiltBy     = "packer"
  }
}

build {
  sources = ["source.amazon-ebs.hardened_ubuntu"]

  provisioner "ansible" {
    playbook_file = "../../ansible/hardening.yml"
    # See the matching comment in the Proxmox template — without this, the
    # plugin's proxy-adapter mode generates an inventory using the local
    # control machine's OS username instead of the actual remote account.
    user = "ubuntu"
    extra_arguments = [
      "--extra-vars", "image_build_date=${local.build_timestamp}"
    ]
  }

  post-processor "shell-local" {
    inline = [
      "echo Built AMI: ${local.image_name}"
    ]
  }
}
