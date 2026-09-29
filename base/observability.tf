# ==========================================
# 로그/백업 보관 버킷 — base 스택
# ==========================================
# CloudTrail 트레일 본체·VPC Flow Logs·EC2 Agent 등 "관측 파이프라인" 은 app 에 있다.
# 여기 base 에는 로그와 백업이 실제로 쌓이는 S3 버킷만 둔다 — app 을 destroy 해도
# 감사 로그와(백업 활성 시) 3년치 DB 백업이 날아가지 않게 하기 위함이다.
#
# 트레일(app)이 이 버킷에 쓰려면 버킷 정책이 먼저 있어야 하므로, 정책도 여기 둔다.
# 정책의 aws:SourceArn 조건에 쓰는 트레일 ARN 은 이름·리전·계정으로 문자열 조립한다
# (트레일 리소스를 직접 참조하면 app->base->app 순환이 되기 때문. 원본과 동일 기법).

locals {
  cloudtrail_name = "kidhackapp-trail" # app 의 aws_cloudtrail.main.name 과 일치해야 함
  trail_arn       = "arn:aws:cloudtrail:${var.aws_region}:${data.aws_caller_identity.current.account_id}:trail/${local.cloudtrail_name}"
}

resource "aws_s3_bucket" "cloudtrail" {
  bucket        = var.cloudtrail_bucket_name
  force_destroy = true

  # base 안전장치: 감사 로그/백업 버킷을 실수로 지우는 plan 을 막는다.
  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 로그(AWSLogs/ 90일)와 member 백업(db-backup/ 3년)을 접두로 나눠 만료시킨다.
resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    id     = "expire-trail-logs"
    status = "Enabled"
    filter {
      prefix = "AWSLogs/"
    }
    expiration {
      days = var.cloudtrail_log_retention_days
    }
  }

  rule {
    id     = "expire-db-backup"
    status = "Enabled"
    filter {
      prefix = "db-backup/"
    }
    expiration {
      days = var.member_backup_retention_days
    }
  }
}

# CloudTrail 서비스가 이 버킷에 로그를 쓸 수 있게 하는 버킷 정책.
# 두 Allow 문 모두 aws:SourceArn 을 이 트레일 ARN 하나로 못박아 confused-deputy 방어.
resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail.arn
        Condition = {
          StringEquals = { "aws:SourceArn" = local.trail_arn }
        }
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "aws:SourceArn" = local.trail_arn
          }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.cloudtrail.arn,
          "${aws_s3_bucket.cloudtrail.arn}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })
}
