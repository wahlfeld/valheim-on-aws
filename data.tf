data "aws_iam_policy" "ssm" {
  arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_route53_zone" "selected" {
  count = var.use_domain ? 1 : 0
  name  = "cwahlfeld.com."
}
