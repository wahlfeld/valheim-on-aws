variable "admins" {
  type        = map(any)
  default     = { "default_valheim_user" = "", }
  description = "List of AWS users/Valheim server admins (use their SteamID)"
}

variable "aws_region" {
  type        = string
  description = "The AWS region to create the Valheim server"
}

variable "domain" {
  type        = string
  default     = ""
  description = "Domain name used to create a static monitoring URL"
}

variable "instance_type" {
  type        = string
  default     = "t3a.medium"
  description = "AWS EC2 instance type to run the server on (t3a.medium is the minimum size)"
}

variable "pgp_key" {
  type        = string
  default     = "keybase:marypoppins"
  description = "The base64 encoded PGP public key to encrypt AWS user passwords with. Can use keybase syntax, e.g., 'keybase:username'."
}

variable "purpose" {
  type        = string
  default     = "prod"
  description = "The purpose of the deployment"
}

variable "s3_lifecycle_expiration" {
  type        = string
  default     = "90"
  description = "The number of days to keep files (backups) in the S3 bucket before deletion"
}

variable "server_name" {
  type        = string
  description = "The server name"
}

variable "server_password" {
  type        = string
  description = "The server password"
}

variable "sns_email" {
  type        = string
  description = "The email address to send alerts to"
}

variable "unique_id" {
  type        = string
  default     = ""
  description = "The ID of the deployment (used for tests)"
}

variable "world_name" {
  type        = string
  description = "The Valheim world name"
}
