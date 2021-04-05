#tfsec:ignore:AWS002 tfsec:ignore:AWS017
resource "aws_s3_bucket" "valheim" {
  count = var.purpose != "test" ? 1 : 0

  bucket = "wahlfeld-${local.name}"
  acl    = "private"
  tags   = merge(local.tags, {})
  versioning { enabled = true }
  lifecycle { prevent_destroy = true }
}

#tfsec:ignore:AWS002 tfsec:ignore:AWS017
resource "aws_s3_bucket" "valheim_test" {
  count = var.purpose == "test" ? 1 : 0

  bucket = "wahlfeld-${local.name}"
  acl    = "private"
  tags   = merge(local.tags, {})
  versioning { enabled = true }
}

resource "aws_s3_bucket_policy" "valheim" {
  bucket = local.bucket_id
  policy = jsonencode({
    Version : "2012-10-17",
    Id : "PolicyForValheimBackups",
    Statement : [
      {
        Effect : "Allow",
        Principal : {
          "AWS" : aws_iam_role.valheim.arn
        },
        Action : [
          "s3:Put*",
          "s3:Get*",
          "s3:List*"
        ],
        Resource : "arn:aws:s3:::${local.bucket_id}/*"
      }
    ]
  })
}

resource "aws_s3_bucket_object" "install_valheim" {
  bucket         = local.bucket_id
  key            = "/install_valheim.sh"
  content_base64 = base64encode(templatefile("${path.module}/local/install_valheim.sh", { username = local.username }))
  etag           = filemd5("${path.module}/local/install_valheim.sh")
}

resource "aws_s3_bucket_object" "bootstrap_valheim" {
  bucket = local.bucket_id
  key    = "/bootstrap_valheim.sh"
  content_base64 = base64encode(templatefile("${path.module}/local/bootstrap_valheim.sh", {
    username = local.username
    bucket   = local.bucket_id
  }))
  etag = filemd5("${path.module}/local/bootstrap_valheim.sh")
}

resource "aws_s3_bucket_object" "start_valheim" {
  bucket = local.bucket_id
  key    = "/start_valheim.sh"
  content_base64 = base64encode(templatefile("${path.module}/local/start_valheim.sh", {
    username        = local.username
    bucket          = local.bucket_id
    use_domain      = var.domain != "" ? true : false
    world_name      = var.world_name
    server_name     = var.server_name
    server_password = var.server_password
  }))
  etag = filemd5("${path.module}/local/start_valheim.sh")
}

resource "aws_s3_bucket_object" "backup_valheim" {
  bucket = local.bucket_id
  key    = "/backup_valheim.sh"
  content_base64 = base64encode(templatefile("${path.module}/local/backup_valheim.sh", {
    username = local.username
    bucket   = local.bucket_id
  }))
  etag = filemd5("${path.module}/local/backup_valheim.sh")
}

resource "aws_s3_bucket_object" "crontab" {
  bucket         = local.bucket_id
  key            = "/crontab"
  content_base64 = base64encode(templatefile("${path.module}/local/crontab", { username = local.username }))
  etag           = filemd5("${path.module}/local/crontab")
}

resource "aws_s3_bucket_object" "valheim_service" {
  bucket         = local.bucket_id
  key            = "/valheim.service"
  content_base64 = base64encode(templatefile("${path.module}/local/valheim.service", { username = local.username }))
  etag           = filemd5("${path.module}/local/valheim.service")
}

resource "aws_s3_bucket_object" "admin_list" {
  bucket         = local.bucket_id
  key            = "/adminlist.txt"
  content_base64 = base64encode(templatefile("${path.module}/local/adminlist.txt", { admins = values(var.admins) }))
  etag           = filemd5("${path.module}/local/adminlist.txt")
}

resource "aws_s3_bucket_object" "update_cname_json" {
  count = var.domain != "" ? 1 : 0

  bucket         = local.bucket_id
  key            = "/update_cname.json"
  content_base64 = base64encode(templatefile("${path.module}/local/update_cname.json", { fqdn = format("%s%s", "valheim.", var.domain) }))
  etag           = filemd5("${path.module}/local/update_cname.json")
}

resource "aws_s3_bucket_object" "update_cname" {
  count = var.domain != "" ? 1 : 0

  bucket = local.bucket_id
  key    = "/update_cname.sh"
  content_base64 = base64encode(templatefile("${path.module}/local/update_cname.sh", {
    username   = local.username
    aws_region = var.aws_region
    bucket     = local.bucket_id
    zone_id    = data.aws_route53_zone.selected[0].zone_id
  }))
  etag = filemd5("${path.module}/local/update_cname.sh")
}

output "bucket_id" {
  value       = local.bucket_id
  description = "The S3 bucket name"
}
