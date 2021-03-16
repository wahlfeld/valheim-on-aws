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
        Resource : "arn:aws:s3:::wahlfeld-valheim/*"
      }
    ]
  })
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
    aws_region = var.aws_region
    bucket     = var.bucket
    zone_id    = data.aws_route53_zone.selected[0].zone_id
  }))
  etag = filemd5("./local/update_cname.sh")
}
