#tfsec:ignore:AWS016
resource "aws_sns_topic" "valheim" {
  name = "${local.name}-status"
  tags = merge(local.tags, {})
}

resource "aws_sns_topic_subscription" "valheim" {
  topic_arn = aws_sns_topic.valheim.arn
  protocol  = "email"
  endpoint  = var.sns_email
}

data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_metric_alarm" "valheim_stopping" {
  alarm_name          = "${local.name}-stopping"
  alarm_description   = "Will stop the Valheim server after a period of inactivity"
  comparison_operator = "LessThanThreshold"
  datapoints_to_alarm = "3"
  evaluation_periods  = "3"
  metric_name         = "NetworkIn"
  period              = "300"
  statistic           = "Average"
  namespace           = "AWS/EC2"
  threshold           = "50000"
  alarm_actions = [
    aws_sns_topic.valheim.arn,
    "arn:aws:swf:ap-southeast-2:${data.aws_caller_identity.current.account_id}:action/actions/AWS_EC2.InstanceId.Stop/1.0",
  ]
  dimensions = { "InstanceId" = aws_instance.valheim.id }
  tags       = merge(local.tags, {})
}

resource "aws_cloudwatch_event_rule" "valheim_starting" {
  name        = "${local.name}-starting"
  description = "Used to trigger notifications when the Valheim server starts"
  event_pattern = jsonencode({
    source : ["aws.ec2"],
    "detail-type" : ["EC2 Instance State-change Notification"],
    detail : {
      state : ["pending"],
      "instance-id" : [aws_instance.valheim.id]
    }
  })
  tags = merge(local.tags, {})
}

resource "aws_cloudwatch_event_target" "valheim_starting" {
  rule      = aws_cloudwatch_event_rule.valheim_starting.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.valheim.arn
  input_transformer {
    input_paths = {
      "account"     = "$.account"
      "instance-id" = "$.detail.instance-id"
      "region"      = "$.region"
      "state"       = "$.detail.state"
      "time"        = "$.time"
    }
    input_template = "\"At <time>, the status of your EC2 instance <instance-id> on account <account> in the AWS Region <region> has changed to <state>.\""
  }
}

data "aws_route53_zone" "selected" {
  count = var.domain != "" ? 1 : 0

  name = "${var.domain}."
}

resource "aws_route53_record" "valheim" {
  count = var.domain != "" ? 1 : 0

  zone_id = data.aws_route53_zone.selected[0].zone_id
  name    = local.name
  type    = "CNAME"
  ttl     = "300"
  records = [aws_instance.valheim.public_dns]
}

output "monitoring_url" {
  value = format("%s%s%s", "http://", var.domain != "" ? aws_route53_record.valheim[0].fqdn : aws_instance.valheim.public_dns, ":19999")
}
