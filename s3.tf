resource "aws_s3_bucket_policy" "valheim" {
  bucket = var.bucket
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
        Resource : "arn:aws:s3:::${var.bucket}/*"
      }
    ]
  })
}

resource "aws_s3_bucket_object" "install_valheim" {
  bucket         = var.bucket
  key            = "/install_valheim.sh"
  content_base64 = base64encode(templatefile("./local/install_valheim.sh", { username = local.username }))
  etag           = filemd5("./local/install_valheim.sh")
}

resource "aws_s3_bucket_object" "bootstrap_valheim" {
  bucket = var.bucket
  key    = "/bootstrap_valheim.sh"
  content_base64 = base64encode(templatefile("./local/bootstrap_valheim.sh", {
    username = local.username
    bucket   = var.bucket
  }))
  etag = filemd5("./local/bootstrap_valheim.sh")
}

resource "aws_s3_bucket_object" "start_valheim" {
  bucket = var.bucket
  key    = "/start_valheim.sh"
  content_base64 = base64encode(templatefile("./local/start_valheim.sh", {
    username        = local.username
    bucket          = var.bucket
    use_domain      = var.domain != "" ? true : false
    world_name      = var.world_name
    server_name     = var.server_name
    server_password = var.server_password
  }))
  etag = filemd5("./local/start_valheim.sh")
}

resource "aws_s3_bucket_object" "backup_valheim" {
  bucket = var.bucket
  key    = "/backup_valheim.sh"
  content_base64 = base64encode(templatefile("./local/backup_valheim.sh", {
    username = local.username
    bucket   = var.bucket
  }))
  etag = filemd5("./local/backup_valheim.sh")
}

resource "aws_s3_bucket_object" "crontab" {
  bucket         = var.bucket
  key            = "/crontab"
  content_base64 = base64encode(templatefile("./local/crontab", { username = local.username }))
  etag           = filemd5("./local/crontab")
}

resource "aws_s3_bucket_object" "valheim_service" {
  bucket         = var.bucket
  key            = "/valheim.service"
  content_base64 = base64encode(templatefile("./local/valheim.service", { username = local.username }))
  etag           = filemd5("./local/valheim.service")
}

resource "aws_s3_bucket_object" "admin_list" {
  bucket         = var.bucket
  key            = "/adminlist.txt"
  content_base64 = base64encode(templatefile("./local/adminlist.txt", { admins = values(var.admins) }))
  etag           = filemd5("./local/adminlist.txt")
}

resource "aws_s3_bucket_object" "update_cname_json" {
  count = var.domain != "" ? 1 : 0

  bucket         = var.bucket
  key            = "/update_cname.json"
  content_base64 = base64encode(templatefile("./local/update_cname.json", { fqdn = format("%s%s", "valheim.", var.domain) }))
  etag           = filemd5("./local/update_cname.json")
}

resource "aws_s3_bucket_object" "update_cname" {
  count = var.domain != "" ? 1 : 0

  bucket = var.bucket
  key    = "/update_cname.sh"
  content_base64 = base64encode(templatefile("./local/update_cname.sh", {
    username   = local.username
    aws_region = var.aws_region
    bucket     = var.bucket
    zone_id    = data.aws_route53_zone.selected[0].zone_id
  }))
  etag = filemd5("./local/update_cname.sh")
}
