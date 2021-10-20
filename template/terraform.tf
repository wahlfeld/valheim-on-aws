terraform {
  required_version = "~> 1.0"

  backend "s3" {
    # bucket = "CHANGEME"
    # key    = "valheim-server/prod/terraform.tfstate"
    # region = "CHANGEME"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
