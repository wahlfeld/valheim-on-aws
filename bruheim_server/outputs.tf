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

output "valheim_server_name" {
  value       = var.server_name
  description = "Name of the Valheim server"
}
