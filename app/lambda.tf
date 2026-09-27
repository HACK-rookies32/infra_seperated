
locals {
  helper_count    = var.enable_deploy_helper ? 1 : 0
  ops_admin_count = var.enable_deploy_helper && var.enable_ops_admin ? 1 : 0
}

resource "aws_iam_role" "deploy_helper" {          # (예시) 라벨
  count = local.helper_count
  name  = "kidhackapp-deploy-helper-role"          # (예시) 역할명
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "deploy_helper_logs" {
  count      = local.helper_count
  role       = aws_iam_role.deploy_helper[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "deploy_helper_perms" {
  count = local.helper_count
  name  = "kidhackapp-deploy-helper-perms"         # (예시) 정책명
  role  = aws_iam_role.deploy_helper[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Resource = "*"
        Action = [
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:ModifyListener"
        ]
      },
      {
        Effect   = "Allow"
        Resource = "*"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeImages",
          "ec2:RunInstances",
          "ec2:AuthorizeSecurityGroupIngress"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = ["${local.base.media_bucket_arn}/*"]
      }
    ]
  })
}

resource "aws_lambda_function" "deploy_helper" {   # (예시) 라벨
  count            = local.helper_count
  function_name    = "kidhackapp-deploy-helper"     # (예시) 함수명 — AWS에 찍히므로 자연스러운 이름 권장
  role             = aws_iam_role.deploy_helper[0].arn
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"       # zip 안 파일명/함수명과 일치시킬 것
  filename         = var.deploy_helper_zip_path
  source_code_hash = var.deploy_helper_zip_path != "" ? filebase64sha256(var.deploy_helper_zip_path) : null
  timeout          = 30
  memory_size      = 256

  environment {
    variables = merge(
      { MEDIA_BUCKET = local.base.media_bucket_id },
      local.ops_admin_count == 1 ? { ADMIN_KEY_PARAM = one(aws_ssm_parameter.ops_admin[*].name) } : {}
    )
  }

  lifecycle {
    precondition {
      condition     = var.deploy_helper_zip_path != ""
      error_message = "enable_deploy_helper=true 면 deploy_helper_zip_path(Lambda zip 경로)를 지정해야 합니다."
    }
  }
}


# studentAdmin 정책이 iam:DeleteUser 를 명시적 Deny 하므로 사용자는 destroy 불가.
# 사용자는 계정에 상시 존재하는 것으로 보고 조회만 하고, 키·정책만 Terraform이 생성/삭제한다.
data "aws_iam_user" "ops_admin" {                   # (예시) 라벨
  count     = local.ops_admin_count
  user_name = "kidhackapp-ops-admin"                # (예시) 사용자명 — AWS에 찍히므로 자연스러운 이름 권장
}

resource "aws_iam_access_key" "ops_admin" {
  count = local.ops_admin_count
  user  = data.aws_iam_user.ops_admin[0].user_name
}

resource "aws_ssm_parameter" "ops_admin" {
  count = local.ops_admin_count
  name  = "/kidhackapp/ops/admin-key"               # (예시) SSM 경로 — 기존 7개 파라미터와 안 겹치게만
  type  = "SecureString"
  value = jsonencode({
    id     = aws_iam_access_key.ops_admin[0].id
    secret = aws_iam_access_key.ops_admin[0].secret
  })
}

resource "aws_iam_user_policy" "ops_admin" {
  count = local.ops_admin_count
  name  = "kidhackapp-ops-admin-policy"             # (예시) 정책명
  user  = data.aws_iam_user.ops_admin[0].user_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [local.base.secure_share_bucket_arn, "${local.base.secure_share_bucket_arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["cloudtrail:StopLogging", "cloudtrail:DeleteTrail"]
        Resource = aws_cloudtrail.main.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:DeleteObject"]
        Resource = "${local.base.cloudtrail_bucket_arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "deploy_helper_read_admin_key" {
  count = local.ops_admin_count
  name  = "kidhackapp-deploy-helper-read-admin-key" # (예시) 정책명
  role  = aws_iam_role.deploy_helper[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["ssm:GetParameter"], Resource = aws_ssm_parameter.ops_admin[0].arn },
      {
        Effect    = "Allow"
        Action    = "kms:Decrypt"
        Resource  = "*"
        Condition = { StringEquals = { "kms:ViaService" = "ssm.${var.aws_region}.amazonaws.com" } }
      }
    ]
  })
}
