terraform {
  required_version = "~> 1.0"

  backend "s3" {
    bucket = "bruheim-world-2023"
    key    = "valheim-server/prod/terraform.tfstate"
    region = "us-east-2"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
