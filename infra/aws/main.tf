# AWS target — real, managed EKS using the two most widely adopted
# community modules on the Terraform Registry:
#   terraform-aws-modules/vpc/aws  and  terraform-aws-modules/eks/aws
# These are the de facto standard for standing up EKS via Terraform and are
# what most real-world AWS shops use rather than hand-rolling the
# equivalent raw resources.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Same "ask for the newest matching image" pattern as the Proxmox external
# lookup script, except AWS's own provider supports this natively — no
# workaround needed here.
data "aws_ami" "latest_hardened" {
  most_recent = true
  owners      = ["self"] # the AMI built by image-pipeline/packer/aws lands in this same account

  filter {
    name   = "name"
    values = ["homelab-hardened-ubuntu-24-04-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.8"

  name = "homelab-pipeline-vpc"
  cidr = "10.42.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnets = ["10.42.1.0/24", "10.42.2.0/24"]
  public_subnets  = ["10.42.101.0/24", "10.42.102.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true # cost-saver for a homelab-scale experiment; use one per AZ in production
  enable_dns_hostnames = true

  # Required tags for EKS to auto-discover subnets for load balancers
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = "homelab-pipeline"
  cluster_version = "1.30"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true # fine for a personal lab; restrict in anything real

  eks_managed_node_groups = {
    hardened = {
      # This is the direct equivalent of the enterprise "AMI lookup feeds
      # the EKS node group's launch template" pattern. AMI_TYPE = CUSTOM
      # tells the module "don't use an AWS-managed EKS-optimized AMI,
      # use the one I built and hardened myself."
      ami_type       = "CUSTOM"
      ami_id         = data.aws_ami.latest_hardened.id
      instance_types = ["t3.small"]

      min_size     = 1
      max_size     = 2
      desired_size = 1

      # A custom (non-EKS-optimized) AMI needs its own bootstrap command to
      # actually join the cluster - the standard EKS-optimized AMIs do this
      # automatically via a baked-in bootstrap script, but a general-purpose
      # hardened Ubuntu image needs it added explicitly here.
      bootstrap_extra_args = "--container-runtime containerd"
    }
  }
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

module "sample_app" {
  source = "../modules/k8s-app"

  app_name       = "sample-app"
  namespace      = "default"
  initial_image  = var.initial_image
  container_port = 8080
  service_type   = "LoadBalancer" # AWS provisions a real ELB here, unlike local/Proxmox
}
