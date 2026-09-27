# ============================================================================
# member 테이블 월간 백업 (운영 기능) — app 스택, 기본 off
# ----------------------------------------------------------------------------
# 전 리소스가 var.enable_member_backup(기본 false)로 게이팅된다. 백업 산출물은
# base 의 cloudtrail 버킷 db-backup/ 에 쌓이므로, app 을 내려도 백업은 남는다.
# (핸들러 zip 은 팀 제공 — var.member_backup_zip_path)
# ============================================================================

locals {
  member_backup_count = var.enable_member_backup ? 1 : 0
}

resource "aws_security_group" "member_backup_sg" {
  count  = local.member_backup_count
  name   = "kidhackapp-member-backup-lambda-sg"
  vpc_id = local.base.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "kidhackapp-member-backup-lambda-sg" }
}

# base 의 rds_sg 에 백업 람다 SG 소스로 1521 인그레스를 붙인다(standalone, 게이팅).
resource "aws_vpc_security_group_ingress_rule" "rds_from_member_backup" {
  count                        = local.member_backup_count
  security_group_id            = local.base.rds_sg_id
  referenced_security_group_id = aws_security_group.member_backup_sg[0].id
  from_port                    = 1521
  to_port                      = 1521
  ip_protocol                  = "tcp"
  description                  = "member backup lambda to Oracle 1521"
}

resource "aws_iam_role" "member_backup_exec" {
  count = local.member_backup_count
  name  = "kidhackapp-member-backup-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "member_backup_basic" {
  count      = local.member_backup_count
  role       = aws_iam_role.member_backup_exec[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "member_backup_vpc" {
  count      = local.member_backup_count
  role       = aws_iam_role.member_backup_exec[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# 최소 권한 3가지(원본 backup.tf 주석 참고).
resource "aws_iam_role_policy" "member_backup" {
  count = local.member_backup_count
  name  = "kidhackapp-member-backup-policy"
  role  = aws_iam_role.member_backup_exec[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadRdsPassword"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = local.base.ssm_param_arns.db_password
      },
      {
        Sid      = "DecryptSecureString"
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ssm.${var.aws_region}.amazonaws.com"
          }
        }
      },
      {
        Sid      = "WriteBackupObjects"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${local.base.cloudtrail_bucket_arn}/db-backup/*"
      }
    ]
  })
}

resource "aws_lambda_function" "member_backup" {
  count         = local.member_backup_count
  function_name = "kidhackapp-member-backup"
  role          = aws_iam_role.member_backup_exec[0].arn
  filename      = var.member_backup_zip_path
  handler       = var.member_backup_handler
  runtime       = var.member_backup_runtime
  timeout       = 300
  memory_size   = 256

  source_code_hash = var.member_backup_zip_path != "" ? filebase64sha256(var.member_backup_zip_path) : null

  vpc_config {
    subnet_ids         = local.base.was_private_subnet_ids
    security_group_ids = [aws_security_group.member_backup_sg[0].id]
  }

  environment {
    variables = {
      DB_HOST           = local.base.rds_address
      DB_PORT           = "1521"
      DB_SID            = var.oracle_db_name
      DB_USER           = var.db_username
      DB_PASSWORD_PARAM = local.base.ssm_param_names.db_password
      BACKUP_BUCKET     = local.base.cloudtrail_bucket_id
      BACKUP_PREFIX     = "db-backup/"
    }
  }

  lifecycle {
    precondition {
      condition     = var.member_backup_zip_path != ""
      error_message = "enable_member_backup=true 이면 var.member_backup_zip_path(백업 핸들러 zip 경로)를 지정해야 합니다."
    }
  }

  tags = { Name = "kidhackapp-member-backup" }
}

resource "aws_cloudwatch_event_rule" "member_backup_monthly" {
  count               = local.member_backup_count
  name                = "kidhackapp-member-backup-monthly"
  description         = "매월 1일 member 테이블 백업 트리거"
  schedule_expression = var.member_backup_schedule
}

resource "aws_cloudwatch_event_target" "member_backup" {
  count     = local.member_backup_count
  rule      = aws_cloudwatch_event_rule.member_backup_monthly[0].name
  target_id = "member-backup-lambda"
  arn       = aws_lambda_function.member_backup[0].arn
}

resource "aws_lambda_permission" "member_backup_events" {
  count         = local.member_backup_count
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.member_backup[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.member_backup_monthly[0].arn
}
