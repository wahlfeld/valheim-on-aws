resource "aws_iam_role" "valheim" {
  name = "valheim-server"
  assume_role_policy = jsonencode({
    Version : "2012-10-17",
    Statement : [
      {
        Action : "sts:AssumeRole",
        Principal : {
          Service : "ec2.amazonaws.com"
        },
        Effect : "Allow",
        Sid : ""
      }
    ]
  })
  tags = merge(local.tags,
    {}
  )
}

resource "aws_iam_instance_profile" "valheim" {
  role = aws_iam_role.valheim.name
}

resource "aws_iam_policy" "valheim" {
  name        = "valheim-server"
  description = "Allows the Valheim server to interact with various AWS services"
  policy = jsonencode({
    Version : "2012-10-17",
    Statement : [
      {
        Effect : "Allow",
        Action : [
          "s3:Put*",
          "s3:Get*",
          "s3:List*"
        ],
        Resource : [
          "arn:aws:s3:::wahlfeld-valheim",
          "arn:aws:s3:::wahlfeld-valheim/"
        ]
      },
      {
        Effect : "Allow",
        Action : [
          "ec2:DescribeInstances"
        ],
        Resource : [
          "*"
        ]
      },
      {
        Action : [
          "route53:ChangeResourceRecordSets"
        ],
        Effect : "Allow",
        Resource : [
          "arn:aws:route53:::hostedzone/${data.aws_route53_zone.selected[0].zone_id}"
        ]
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "valheim" {
  name       = "valheim"
  roles      = [aws_iam_role.valheim.name]
  policy_arn = aws_iam_policy.valheim.arn
}

data "aws_iam_policy" "ssm" {
  arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_policy_attachment" "ssm" {
  name       = "valheim-ssm"
  roles      = [aws_iam_role.valheim.name]
  policy_arn = data.aws_iam_policy.ssm.arn
}

resource "aws_iam_group" "valheim_users" {
  name = "valheim-users"
  path = "/users/"
}

resource "aws_iam_policy" "valheim_users" {
  name        = "valheim-user"
  description = "Allows Valheim users to start the server"
  policy = jsonencode({
    Version = "2012-10-17"
    "Statement" : [
      {
        Effect : "Allow",
        Action : [
          "ec2:StartInstances"
        ],
        Resource : aws_instance.valheim.arn,
      },
      {
        Effect : "Allow",
        Action : [
          "cloudwatch:DescribeAlarms",
          "ec2:DescribeAddresses",
          "ec2:DescribeInstanceAttribute",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeInstances",
          "ec2:DescribeKeyPairs",
          "ec2:DescribeNetworkInterfaces"
        ]
        Resource : "*"
      }
    ]
  })
}

resource "aws_iam_group_policy_attachment" "valheim_users" {
  group      = aws_iam_group.valheim_users.name
  policy_arn = aws_iam_policy.valheim_users.arn
}

# resource "aws_iam_user" "valheim_user" {
#   for_each = var.admins

#   name          = each.key
#   path          = "/"
#   force_destroy = true
#   tags = merge(local.tags,
#     {}
#   )
# }

# resource "aws_iam_user_login_profile" "valheim_user" {
#   for_each = aws_iam_user.valheim_user

#   user    = aws_iam_user.valheim_user[each.key].name
#   pgp_key = "keybase:wahlfeld"
# }

# resource "aws_iam_user_group_membership" "valheim_users" {
#   for_each = aws_iam_user.valheim_user

#   user = aws_iam_user.valheim_user[each.key].name
#   groups = [
#     aws_iam_group.valheim_users.name,
#   ]
# }

# output "valheim_user_passwords" {
#   value = { for i in aws_iam_user_login_profile.valheim_user : i.user => i.encrypted_password }
# }
