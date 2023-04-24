locals {
  username = "vhserver"
  tags = {
    "Purpose"   = var.purpose
    "Component" = "Valheim Server"
    "CreatedBy" = "Terraform"
  }
  ec2_tags = merge(local.tags,
    {
      "Name"        = "${local.name}-server"
      "Description" = "Instance running a Valheim server"
    }
  )
  name       = var.purpose != "prod" ? "valheim-${var.purpose}${var.unique_id}" : "valheim"
  use_domain = var.domain != "" ? true : false
}

variable "admins" {
  type = map(any)
}

variable "aws_region" {
  type = string
}

variable "domain" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "pgp_key" {
  type = string
}

variable "purpose" {
  type = string
}

variable "s3_lifecycle_expiration" {
  type = string
}

variable "server_name" {
  type = string
}

variable "server_password" {
  type = string
}

variable "sns_email" {
  type = string
}

variable "unique_id" {
  type = string
}

variable "world_name" {
  type = string
}
