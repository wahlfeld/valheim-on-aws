module "main" {
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
