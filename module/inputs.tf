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

variable "keybase_username" {
  type        = string
  description = "The Keybase username to encrypt AWS user passwords with"
}

variable "instance_type" {
  type        = string
  default     = "t3a.medium"
  description = "AWS EC2 instance type to run the server on (t3a.medium is the minimum size)"
}

variable "sns_email" {
  type        = string
  description = "The email address to send alerts to"
}

variable "world_name" {
  type        = string
  description = "The Valheim world name"
}

variable "server_name" {
  type        = string
  description = "The server name"
}

variable "server_password" {
  type        = string
  description = "The server password"
}

variable "purpose" {
  type        = string
  default     = "prod"
  description = "The purpose of the deployment"
}

variable "unique_id" {
  type        = string
  default     = ""
  description = "The ID of the deployment (used for tests)"
}

locals {
  username = "vhserver"
  tags = {
    "Purpose"   = var.purpose
    "Component" = "Valheim Server"
    "CreatedBy" = "Terraform"
  }
  name = var.purpose != "prod" ? "valheim-${var.purpose}${var.unique_id}" : "valheim"
}
