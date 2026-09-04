# AWS Target

Real, managed EKS using `terraform-aws-modules/vpc/aws` and
`terraform-aws-modules/eks/aws` — the two most widely used community
modules for this, and what most real AWS shops reach for rather than
hand-rolling the equivalent raw `aws_*` resources.

## Cost warning

This is the one target in this repo that costs real money continuously
while running: an EKS control plane is ~$0.10/hr (~$73/mo) on its own, plus
the worker node(s), NAT gateway, and EBS volumes. Budget roughly $100-150/mo
if left running, or **`terraform destroy` between sessions** — this is a
learning environment, not something to leave up idle.

## A fidelity gap worth knowing about before you run this

The Packer AWS template in this repo (`image-pipeline/packer/aws`)
hardens a **stock Canonical Ubuntu AMI**. That is enough to prove the
"hardening + agent baked in at build time" half of the pattern, but a
stock Ubuntu AMI is **not**, by itself, ready to join an EKS cluster as a
worker node — it's missing `kubelet`, `containerd`, the CNI plugins, and
AWS's own EKS bootstrap script that a real EKS-optimized AMI includes.

The real-world version of this pattern (and the honest way to close this
gap if you want this to actually join a cluster) starts hardening **from
one of AWS's own published `amazon-eks-node-*` AMIs** instead of a stock
Ubuntu image — those already contain everything needed to join a cluster,
and your Ansible hardening playbook just adds the security layer on top,
the same way the enterprise pipeline this repo is modeled on does it. This
repo's Packer AWS template uses stock Ubuntu specifically because it's the
simplest possible example to read and understand the *hardening* step in
isolation — treat swapping the source AMI as the very next thing to do
before actually trying to run this against EKS for real.

## Prerequisites

- An AWS account with permissions for VPC, EKS, EC2, IAM (the module
  creates IAM roles/policies for the cluster and node group)
- `aws` CLI configured
- At least one hardened AMI already built (see the fidelity gap above
  before relying on it for real EKS nodes)

## Apply

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

## After apply

```bash
aws eks update-kubeconfig --name homelab-pipeline --region us-east-1
kubectl get nodes
kubectl get deployment,svc,hpa -n default
```

## Tearing down

```bash
terraform destroy
```
