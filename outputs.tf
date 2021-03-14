# output "valheim_user_passwords" {
#   value = { for i in aws_iam_user_login_profile.valheim_user : i.user => i.encrypted_password }
# }

output "monitoring_url" {
  value = format("%s%s%s", "http://", try(aws_route53_record.valheim[0].fqdn, aws_instance.valheim.public_dns), ":19999")
}
