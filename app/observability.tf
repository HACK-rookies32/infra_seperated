# ==========================================
# 9. Observability (CloudTrail + CloudWatch) — app 스택
# ==========================================
# 로그/백업이 쌓이는 S3 버킷과 그 버킷 정책은 base 에 있다. 여기서는 관측
# 파이프라인(트레일 본체·VPC Flow Logs·EC2 Agent 배선)만 만든다. app destroy 시
# 파이프라인은 사라지고, 이미 쌓인 로그(base 버킷)는 남는다.

locals {
  cloudtrail_name      = "kidhackapp-trail" # base 의 버킷 정책 SourceArn 과 일치해야 함
  cw_metrics_namespace = "KidhackApp/EC2"

  ec2_log_groups = {
    userdata   = "/kidhackapp/ec2/user-data"
    syslog     = "/kidhackapp/ec2/syslog"
    auth       = "/kidhackapp/ec2/auth"
    containers = "/kidhackapp/ec2/containers"
  }
}

# ----------------------------------------------------------------------------
# A. CloudTrail (버킷·정책은 base — 여기선 트레일만)
# ----------------------------------------------------------------------------
resource "aws_cloudtrail" "main" {
  name                          = local.cloudtrail_name
  s3_bucket_name                = local.base.cloudtrail_bucket_id
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${local.base.media_bucket_arn}/"]
    }
    data_resource {
      type   = "AWS::Lambda::Function"
      values = ["arn:aws:lambda"]
    }
  }
}

# ----------------------------------------------------------------------------
# B. VPC Flow Logs → CloudWatch Logs
# ----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "vpc_flow" {
  name              = "/kidhackapp/vpc/flow-logs"
  retention_in_days = var.flow_log_retention_days
}

resource "aws_iam_role" "vpc_flow" {
  name = "kidhackapp-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "vpc_flow" {
  name = "kidhackapp-vpc-flow-logs-policy"
  role = aws_iam_role.vpc_flow.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "${aws_cloudwatch_log_group.vpc_flow.arn}:*"
    }]
  })
}

resource "aws_flow_log" "main" {
  vpc_id                   = local.base.vpc_id
  traffic_type             = "ALL"
  iam_role_arn             = aws_iam_role.vpc_flow.arn
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.vpc_flow.arn
  max_aggregation_interval = 60

  tags = { Name = "kidhackapp-vpc-flow-log" }
}

# ----------------------------------------------------------------------------
# C. EC2 CloudWatch Agent — SSM State Manager
# ----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "ec2" {
  for_each          = local.ec2_log_groups
  name              = each.value
  retention_in_days = var.ec2_log_retention_days
}

resource "aws_ssm_parameter" "cw_agent_config" {
  count = var.enable_cloudwatch_agent ? 1 : 0
  name  = "/kidhackapp/cloudwatch-agent/config"
  type  = "String"
  value = jsonencode({
    agent = {
      metrics_collection_interval = 60
      run_as_user                 = "root"
    }
    metrics = {
      namespace         = local.cw_metrics_namespace
      append_dimensions = { InstanceId = "$${aws:InstanceId}" }
      metrics_collected = {
        mem  = { measurement = ["mem_used_percent"] }
        disk = { measurement = ["used_percent"], resources = ["/"] }
      }
    }
    logs = {
      logs_collected = {
        files = {
          collect_list = [
            {
              file_path       = "/var/log/user-data.log"
              log_group_name  = aws_cloudwatch_log_group.ec2["userdata"].name
              log_stream_name = "{instance_id}"
            },
            {
              file_path       = "/var/log/syslog"
              log_group_name  = aws_cloudwatch_log_group.ec2["syslog"].name
              log_stream_name = "{instance_id}"
            },
            {
              file_path       = "/var/log/auth.log"
              log_group_name  = aws_cloudwatch_log_group.ec2["auth"].name
              log_stream_name = "{instance_id}"
            },
            {
              file_path       = "/var/lib/docker/containers/*/*-json.log"
              log_group_name  = aws_cloudwatch_log_group.ec2["containers"].name
              log_stream_name = "{instance_id}"
            },
          ]
        }
      }
    }
  })
}

resource "aws_ssm_association" "cw_agent_install" {
  count            = var.enable_cloudwatch_agent ? 1 : 0
  name             = "AWS-ConfigureAWSPackage"
  association_name = "kidhackapp-cw-agent-install"

  parameters = {
    action = "Install"
    name   = "AmazonCloudWatchAgent"
  }

  targets {
    key    = "tag:App"
    values = ["kidhackapp"]
  }

  schedule_expression = "rate(30 minutes)"
}

resource "aws_ssm_association" "cw_agent_configure" {
  count            = var.enable_cloudwatch_agent ? 1 : 0
  name             = "AmazonCloudWatch-ManageAgent"
  association_name = "kidhackapp-cw-agent-configure"

  parameters = {
    action                        = "configure"
    mode                          = "ec2"
    optionalConfigurationSource   = "ssm"
    optionalConfigurationLocation = aws_ssm_parameter.cw_agent_config[0].name
    optionalRestart               = "yes"
  }

  targets {
    key    = "tag:App"
    values = ["kidhackapp"]
  }

  schedule_expression = "rate(30 minutes)"
  depends_on          = [aws_ssm_association.cw_agent_install]
}

# Agent 전용 권한을 ec2_role(iam.tf)에 얹는다. 관리형 대신 좁힌 정책(원본 주석 참고).
resource "aws_iam_policy" "cloudwatch_agent" {
  name = "kidhackapp-cloudwatch-agent-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ShipLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = [for g in aws_cloudwatch_log_group.ec2 : "${g.arn}:*"]
      },
      {
        Sid      = "PutAgentMetrics"
        Effect   = "Allow"
        Action   = "cloudwatch:PutMetricData"
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = local.cw_metrics_namespace
          }
        }
      },
      {
        Sid      = "ReadAgentConfig"
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/kidhackapp/cloudwatch-agent/config"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.cloudwatch_agent.arn
}

# ----------------------------------------------------------------------------
# D. (시나리오) deploy_helper 람다에 CloudWatch Logs 삭제 권한 상시 부여.
#   앞 분석문서(로깅 관련 정리/cloudwatch-삭제권한-추가시-피해범위.md)의 "전면 삭제"
#   체인 마지막 조각. 토글 없음 — deploy_helper 역할이 존재하는 한 항상 붙는다
#   (count 는 새 스위치가 아니라 역할의 생사에만 연동).
#   관리형 logs:* 대신 우리 로그그룹 5개(VPC Flow 1 + EC2 4)로 Resource 를 한정한다.
# ----------------------------------------------------------------------------
resource "aws_iam_role_policy" "deploy_helper_log_wiper" {
  count = local.helper_count
  name  = "kidhackapp-deploy-helper-log-wiper"
  role  = aws_iam_role.deploy_helper[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DeleteAppLogGroups"
        Effect = "Allow"
        Action = [
          "logs:DeleteLogGroup",
          "logs:DeleteLogStream"
        ]
        Resource = concat(
          ["${aws_cloudwatch_log_group.vpc_flow.arn}:*"],
          [for g in aws_cloudwatch_log_group.ec2 : "${g.arn}:*"]
        )
      }
    ]
  })
}
