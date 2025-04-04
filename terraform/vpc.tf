module "vpc" {
  count = var.enable_rds ? 1:0
  source  = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git?ref=e226cc15a7b8f62fd0e108792fea66fa85bcb4b9" ##commit hash for v5.13.0
  # source = "terraform-aws-modules/vpc/aws"
  # version = "5.13.0"
  name = "aws-vpc"

  cidr = "10.0.0.0/16"
  azs  = slice(element(data.aws_availability_zones.available.*.names,count.index), 0, 3)

  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  database_subnets = ["10.0.8.0/24", "10.0.9.0/24", "10.0.10.0/24"]

  
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  default_security_group_ingress = [{
      from_port   = 0
      to_port     = 65535
      protocol    = "tcp"
      description = null
      self        = true
    }]
  
  default_security_group_egress = [{
      from_port   = 0
      to_port     = 65535
      protocol    = "tcp"
      description = null
      self        = true
    }]
}
