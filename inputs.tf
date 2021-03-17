variable "aws_region" {
  type        = string
  description = "The AWS region to create the Valheim server"
}

variable "admins" {
  type        = map(any)
  default     = {}
  description = "List of Valheim server admins (use their SteamID)"
}

variable "domain" {
  type        = string
  default     = ""
  description = "Domain name used to create a static monitoring URL"
}

variable "bucket" {
  type        = string
  description = "S3 bucket used for storing backups and other content"
}

locals {
  username = "vhserver"
  tags = {
    "Purpose"   = "Valheim Server"
    "CreatedBy" = "Terraform"
  }
}
