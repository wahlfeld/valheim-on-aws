terraform {
  required_version = "~> 0.14.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "test" {
  source = "../module"

  aws_region       = var.aws_region
  admins           = var.admins
  domain           = var.domain
  keybase_username = var.keybase_username
  instance_type    = var.instance_type
  sns_email        = var.sns_email
  world_name       = var.world_name
  server_name      = var.server_name
  server_password  = var.server_password
  purpose          = var.purpose
  unique_id        = var.unique_id
}
