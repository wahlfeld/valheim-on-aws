module "main" {
  source = "../module"

  admins                  = var.admins
  aws_region              = var.aws_region
  domain                  = var.domain
  instance_type           = var.instance_type
  keybase_username        = var.keybase_username
  purpose                 = var.purpose
  s3_lifecycle_expiration = var.s3_lifecycle_expiration
  server_name             = var.server_name
  server_password         = var.server_password
  sns_email               = var.sns_email
  unique_id               = var.unique_id
  world_name              = var.world_name
}

output "monitoring_url" {
  value       = module.main.monitoring_url
  description = "URL to monitor the Valheim Server"
}

output "bucket_id" {
  value       = module.main.bucket_id
  description = "The S3 bucket name"
}

output "instance_id" {
  value       = module.main.instance_id
  description = "The EC2 instance ID"
}

output "valheim_user_passwords" {
  value       = module.main.valheim_user_passwords
  description = "List of AWS users and their encrypted passwords"
}
