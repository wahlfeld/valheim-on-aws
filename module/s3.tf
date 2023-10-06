#tfsec:ignore:AWS002
resource "aws_s3_bucket" "valheim" {
  #checkov:skip=CKV_AWS_18:Access logging is an extra cost and unecessary for this implementation
  #checkov:skip=CKV_AWS_144:Cross-region replication is an extra cost and unecessary for this implementation
  #checkov:skip=CKV_AWS_52:MFA delete is unecessary for this implementation
  #checkov:skip=CKV2_AWS_62:Event notifications are unecessary for this implementation
  bucket_prefix = local.name
  tags          = local.tags
}

resource "aws_s3_bucket_versioning" "valheim" {
  bucket = aws_s3_bucket.valheim.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_ownership_controls" "valheim" {
  #checkov:skip=CKV2_AWS_65: https://github.com/bridgecrewio/checkov/issues/5623
  bucket = aws_s3_bucket.valheim.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "valheim" {
  #checkov:skip=CKV_AWS_300:Unnecessary to setup a period for aborting failed uploads
  bucket = aws_s3_bucket.valheim.id

  rule {
    id     = "rule-1"
    status = "Enabled"

    expiration {
      days = var.s3_lifecycle_expiration
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "valheim" {
  bucket = aws_s3_bucket.valheim.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_policy" "valheim" {
  bucket = aws_s3_bucket.valheim.id
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
        Resource : "arn:aws:s3:::${aws_s3_bucket.valheim.id}/*"
      }
    ]
  })

  // https://github.com/hashicorp/terraform-provider-aws/issues/7628
  depends_on = [aws_s3_bucket_public_access_block.valheim]
}

resource "aws_s3_bucket_public_access_block" "valheim" {
  bucket = aws_s3_bucket.valheim.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "install_valheim" {
  #checkov:skip=CKV_AWS_186:KMS encryption is not necessary
  bucket         = aws_s3_bucket.valheim.id
  key            = "/install_valheim.sh"
  content_base64 = base64encode(templatefile("${path.module}/local/install_valheim.sh", { username = local.username }))
  etag           = filemd5("${path.module}/local/install_valheim.sh")
}

resource "aws_s3_object" "bootstrap_valheim" {
  #checkov:skip=CKV_AWS_186:KMS encryption is not necessary
  bucket = aws_s3_bucket.valheim.id
  key    = "/bootstrap_valheim.sh"
  content_base64 = base64encode(templatefile("${path.module}/local/bootstrap_valheim.sh", {
    username = local.username
    bucket   = aws_s3_bucket.valheim.id
  }))
  etag = filemd5("${path.module}/local/bootstrap_valheim.sh")
}

resource "aws_s3_object" "start_valheim" {
  #checkov:skip=CKV_AWS_186:KMS encryption is not necessary
  bucket = aws_s3_bucket.valheim.id
  key    = "/start_valheim.sh"
  content_base64 = base64encode(templatefile("${path.module}/local/start_valheim.sh", {
    username        = local.username
    bucket          = aws_s3_bucket.valheim.id
    use_domain      = local.use_domain
    world_name      = var.world_name
    server_name     = var.server_name
    server_password = var.server_password
  }))
  etag = filemd5("${path.module}/local/start_valheim.sh")
}

resource "aws_s3_object" "backup_valheim" {
  #checkov:skip=CKV_AWS_186:KMS encryption is not necessary
  bucket = aws_s3_bucket.valheim.id
  key    = "/backup_valheim.sh"
  content_base64 = base64encode(templatefile("${path.module}/local/backup_valheim.sh", {
    username   = local.username
    bucket     = aws_s3_bucket.valheim.id
    world_name = var.world_name
  }))
  etag = filemd5("${path.module}/local/backup_valheim.sh")
}

resource "aws_s3_object" "crontab" {
  #checkov:skip=CKV_AWS_186:KMS encryption is not necessary
  bucket         = aws_s3_bucket.valheim.id
  key            = "/crontab"
  content_base64 = base64encode(templatefile("${path.module}/local/crontab", { username = local.username }))
  etag           = filemd5("${path.module}/local/crontab")
}

resource "aws_s3_object" "valheim_service" {
  #checkov:skip=CKV_AWS_186:KMS encryption is not necessary
  bucket = aws_s3_bucket.valheim.id
  key    = "/valheim.service"
  content_base64 = base64encode(templatefile("${path.module}/local/valheim.service", {
    username = local.username
  }))
  etag = filemd5("${path.module}/local/valheim.service")
}

resource "aws_s3_object" "admin_list" {
  #checkov:skip=CKV_AWS_186:KMS encryption is not necessary
  bucket         = aws_s3_bucket.valheim.id
  key            = "/adminlist.txt"
  content_base64 = base64encode(templatefile("${path.module}/local/adminlist.txt", { admins = values(var.admins) }))
  etag           = filemd5("${path.module}/local/adminlist.txt")
}

resource "aws_s3_object" "update_cname_json" {
  #checkov:skip=CKV_AWS_186:KMS encryption is not necessary
  count = local.use_domain ? 1 : 0

  bucket         = aws_s3_bucket.valheim.id
  key            = "/update_cname.json"
  content_base64 = base64encode(templatefile("${path.module}/local/update_cname.json", { fqdn = format("%s%s", "valheim.", var.domain) }))
  etag           = filemd5("${path.module}/local/update_cname.json")
}

resource "aws_s3_object" "update_cname" {
  #checkov:skip=CKV_AWS_186:KMS encryption is not necessary
  count = local.use_domain ? 1 : 0

  bucket = aws_s3_bucket.valheim.id
  key    = "/update_cname.sh"
  content_base64 = base64encode(templatefile("${path.module}/local/update_cname.sh", {
    username   = local.username
    aws_region = var.aws_region
    bucket     = aws_s3_bucket.valheim.id
    zone_id    = data.aws_route53_zone.selected[0].zone_id
  }))
  etag = filemd5("${path.module}/local/update_cname.sh")
}

output "bucket_id" {
  value = aws_s3_bucket.valheim.id
}
