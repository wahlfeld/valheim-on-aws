variable "aws_region" {
  type        = string
  description = "The AWS region to create the Valheim server"
}

variable "use_domain" {
  type        = bool
  default     = false
  description = "Whether to create a friendly CNAME that points to the Valheim server"
}

variable "admins" {
  type        = map(any)
  default     = {}
  description = "List of Valheim server admins (use their SteamID)"
}

locals {
  tags = {
    "Purpose"   = "Valheim Server"
    "CreatedBy" = "Terraform"
  }
}
