resource "aws_security_group" "ingress" {
  tags = merge(local.tags,
    {
      "Name"        = "Valheim Ingress"
      "Description" = "Security group allowing inbound traffic to the Valheim server"
    }
  )
}

resource "aws_security_group_rule" "valheim_ingress" {
  type      = "ingress"
  from_port = 2456
  to_port   = 2458
  protocol  = "udp"
  cidr_blocks = [
    "0.0.0.0/0"
  ]
  security_group_id = aws_security_group.ingress.id
  description       = "Allows traffic to the Valheim server"
}

resource "aws_security_group_rule" "netdata" {
  type      = "ingress"
  from_port = 19999
  to_port   = 19999
  protocol  = "tcp"
  cidr_blocks = [
    "0.0.0.0/0"
  ]
  security_group_id = aws_security_group.ingress.id
  description       = "Allows traffic to the Netdata dashboard"
}

resource "aws_security_group_rule" "egress" {
  type      = "egress"
  from_port = 0
  to_port   = 0
  protocol  = "-1"
  cidr_blocks = [
    "0.0.0.0/0"
  ]
  security_group_id = aws_security_group.ingress.id
  description       = "Allow all egress rule for the Valheim server"
}

resource "aws_instance" "valheim" {
  # Free tier eligible: Ubuntu Server 20.04 LTS (HVM), SSD Volume Type
  ami           = "ami-0d767dd04ac152743"
  instance_type = "t3a.medium"
  user_data = templatefile("./local/userdata.sh", {
    use_domain = var.domain != "" ? true : false
  })
  iam_instance_profile = aws_iam_instance_profile.valheim.name
  vpc_security_group_ids = [
    aws_security_group.ingress.id
  ]
  tags = merge(local.tags,
    {
      "Name"        = "Valheim Server"
      "Description" = "Instance running a Valheim server"
    }
  )

  depends_on = [
    aws_s3_bucket_object.admin_list,
    aws_s3_bucket_object.update_cname_json[0],
    aws_s3_bucket_object.update_cname[0]
  ]
}
