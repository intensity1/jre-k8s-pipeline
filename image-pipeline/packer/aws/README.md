# AWS Golden Image — Packer

## Prerequisites

1. An AWS account with an IAM user/role that can: launch/terminate EC2,
   create/describe AMIs and snapshots, describe images. The official
   `AmazonEC2FullAccess` managed policy is more than enough for a homelab
   experiment; scope it down for anything longer-lived.
2. AWS CLI configured (`aws configure` or a named profile +
   `AWS_PROFILE=<name>`).
3. An SSH keypair (Packer injects its own temporary key automatically for
   `amazon-ebs` unless you override it — the default behavior is fine here).

## Build

```bash
cd image-pipeline/packer/aws
cp variables.pkrvars.hcl.example variables.pkrvars.hcl   # optional - all 3 vars have working defaults
packer init .
packer validate -var-file=variables.pkrvars.hcl ubuntu-2404.pkr.hcl
packer build   -var-file=variables.pkrvars.hcl ubuntu-2404.pkr.hcl
```

## Cost note

A `t3.micro` build instance runs for roughly the duration of the Ansible
playbook (a few minutes) and is terminated automatically once the AMI is
created. The ongoing cost is just AMI/snapshot storage (a few cents/month
per image) until you deregister old ones. Prune old AMIs + their snapshots
periodically — Packer does not do this for you.

## What you get

A new AMI named `homelab-hardened-ubuntu-24-04-<timestamp>` in your own
account. `infra/aws/main.tf` looks this up later via a `data "aws_ami"`
block filtering on that same name pattern with `most_recent = true` — the
identical lookup pattern used on the Proxmox side, just against a different
API.
