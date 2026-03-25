terraform{
    required_providers{
        aws = {
            source = "hashicorp/aws"
            version = "~> 5.0"
        }
    }
    required_version = ">= 1.5.0"
    #backend "s3" {
     #   bucket = "tf-state-mjl-k8s"
      #  key    = "eks-cluster/terraform.tfstate"
       # region = "us-east-1"
        #dynamodb_table = "tf-state-lock-mjl-k8s"
   # }
}

provider "aws" {
    region = "us-east-1"
}

#S3 bucket for terraform remote state
resource "aws_s3_bucket" "terraform_state" {
    bucket = "tf-state-mjl-k8s"
}
#enable versioning for the S3 bucket
resource "aws_s3_bucket_versioning" "terraform_state_versioning" {
    bucket = aws_s3_bucket.terraform_state.id
    versioning_configuration {
        status = "Enabled"
    }
}
#Block all public access
resource "aws_s3_bucket_public_access_block" "terraform_state_public_access_block" {
    bucket = aws_s3_bucket.terraform_state.id
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
}
#enable server-side encryption for the S3 bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state_encryption" {
    bucket = aws_s3_bucket.terraform_state.id
    rule {
        apply_server_side_encryption_by_default {
            sse_algorithm = "AES256"
        }
    }
}
#DynamoDB table for terraform state locking
resource "aws_dynamodb_table" "terraform_state_lock" {
    name         = "tf-state-lock-mjl-k8s"
    billing_mode = "PAY_PER_REQUEST"
    hash_key     = "LockID"

    attribute {
        name = "LockID"
        type = "S"
    }
}   

#VPC using the terraform-aws-modules/vpc/aws module
#with two private and two public subnets across two availability zones
module "vpc" {
    source = "terraform-aws-modules/vpc/aws"
    version = "~> 3.0"

    name = "mjl-k8s-vpc"
    cidr = "10.0.0.0/16"
    azs             = ["us-east-1a", "us-east-1b"]
    private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
    public_subnets  = ["10.0.10.0/24", "10.0.11.0/24"]

    public_subnet_tags = {
        "kubernetes.io/cluster/mjl-k8s-cluster" = "shared"
        "kubernetes.io/role/elb" = "1"
    }
    private_subnet_tags = {
        "kubernetes.io/cluster/mjl-k8s-cluster" = "shared"
        "kubernetes.io/role/internal-elb" = "1"
    }
    enable_nat_gateway = true
    single_nat_gateway = true

}

#EKS cluster & security defaults
module "eks" {
    source = "terraform-aws-modules/eks/aws"
    version = "~> 18.0"

    cluster_name    = "mjl-k8s-cluster"
    cluster_version = "1.29"
    vpc_id          = module.vpc.vpc_id

    cluster_endpoint_public_access = true
    cluster_endpoint_public_access_cidrs = ["71.188.67.57/32"]
    cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
    
    subnet_ids = module.vpc.private_subnets
    enable_irsa = true

    eks_managed_node_groups = {
        general = {
            desired_size = 2
            min_size     = 1
            max_size     = 3

            instance_types   = ["t3.medium"]
            ami_type = "BOTTLEROCKET_x86_64"
        }
    }
    create_kms_key = false
    cluster_encryption_config = [{
        resources = ["secrets"]
        provider = aws_kms_key.eks_secrets.arn
    }]
}

resource "aws_kms_key" "eks_secrets" {
    description = "EKS secret encryption key"
    deletion_window_in_days = 7
    enable_key_rotation = true
}