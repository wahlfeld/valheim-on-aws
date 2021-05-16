#tfsec:ignore:AWS018
resource "aws_security_group" "ingress" {
  tags = merge(local.tags,
    {
      "Name"        = "${local.name}-ingress"
      "Description" = "Security group allowing inbound traffic to the Valheim server"
    }
  )
}

resource "aws_security_group_rule" "valheim_ingress" {
  type              = "ingress"
  from_port         = 2456
  to_port           = 2458
  protocol          = "udp"
  cidr_blocks       = ["0.0.0.0/0"] #tfsec:ignore:AWS006
  security_group_id = aws_security_group.ingress.id
  description       = "Allows traffic to the Valheim server"
}

resource "aws_security_group_rule" "netdata" {
  type              = "ingress"
  from_port         = 19999
  to_port           = 19999
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"] #tfsec:ignore:AWS006
  security_group_id = aws_security_group.ingress.id
  description       = "Allows traffic to the Netdata dashboard"
}

resource "aws_security_group_rule" "egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"] #tfsec:ignore:AWS007
  security_group_id = aws_security_group.ingress.id
  description       = "Allow all egress rule for the Valheim server"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.*-amd64-server-*"]
  }
}

resource "aws_instance" "valheim" {
  #checkov:skip=CKV_AWS_126:Detailed monitoring is an extra cost and unecessary for this implementation
  #checkov:skip=CKV_AWS_8:This is not a launch configuration
  #checkov:skip=CKV2_AWS_17:This instance will be placed in the default VPC deliberately
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  ebs_optimized = true
  user_data = templatefile("${path.module}/local/userdata.sh", {
    username = local.username
    bucket   = aws_s3_bucket.valheim.id
  })
  iam_instance_profile   = aws_iam_instance_profile.valheim.name
  vpc_security_group_ids = [aws_security_group.ingress.id]
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  tags = merge(local.tags,
    {
      "Name"        = "${local.name}-server"
      "Description" = "Instance running a Valheim server"
    }
  )

  depends_on = [
    aws_s3_bucket_object.install_valheim,
    aws_s3_bucket_object.start_valheim,
    aws_s3_bucket_object.backup_valheim,
    aws_s3_bucket_object.crontab,
    aws_s3_bucket_object.valheim_service,
    aws_s3_bucket_object.admin_list,
    aws_s3_bucket_object.update_cname_json[0],
    aws_s3_bucket_object.update_cname[0]
  ]
}

output "instance_id" {
  value = aws_instance.valheim.id
}
