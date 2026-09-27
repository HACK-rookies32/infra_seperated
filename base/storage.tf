# ==========================================
# 4. Storage (S3) — base 스택 (사용자 데이터 보존)
# ==========================================
# media(사용자 첨부)·secure_share(중요정보)는 데이터가 쌓이는 버킷이라 base 에 둔다.
# app 을 destroy 해도 이 버킷과 내용은 남는다.
#
# ⚠️ 브라우저 직접 업로드용 CORS 설정(aws_s3_bucket_cors_configuration.media)은
#    허용 오리진이 ALB/도메인(app)에 의존하므로 app 스택으로 옮겼다. base 버킷
#    id 를 참조해 app 이 이 버킷에 CORS 를 붙인다. app destroy 시 CORS 만 사라진다
#    (WAS 가 없어 어차피 업로드가 없으니 무해).

# force_destroy = true : 예전엔 환경 통째 재생성 주기 때문에 유지했으나, 이제 이
# 버킷은 base 라 destroy 대상이 아니다. 그래도 값 자체는 유지한다(정말 base 를
# 내려야 할 때 BucketNotEmpty 로 막히지 않도록). base 는 평소 destroy 하지 않는다.
resource "aws_s3_bucket" "media" {
  bucket        = var.s3_bucket_name
  force_destroy = true

  # base 안전장치: 실수로 이 버킷을 지우는 plan 을 막는다(사용자 첨부 보존).
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "media_ver" {
  bucket = aws_s3_bucket.media.id
  versioning_configuration {
    status = "Enabled"
  }
}

# ==========================================
# 라이프사이클 — 지운 파일이 영원히 남지 않게 한다
# ==========================================
resource "aws_s3_bucket_lifecycle_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  depends_on = [aws_s3_bucket_versioning.media_ver]

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  rule {
    id     = "expire-delete-markers"
    status = "Enabled"
    filter {}
    expiration {
      expired_object_delete_marker = true
    }
  }

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "media_enc" {
  bucket = aws_s3_bucket.media.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 퍼블릭 액세스 차단 4종.
resource "aws_s3_bucket_public_access_block" "media" {
  bucket = aws_s3_bucket.media.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 전송 암호화 강제: HTTP(비 TLS) 요청은 거부한다.
resource "aws_s3_bucket_policy" "media_tls_only" {
  bucket = aws_s3_bucket.media.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.media.arn,
        "${aws_s3_bucket.media.arn}/*"
      ]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })
}

# ==========================================
# 중요정보 공유용 프라이빗 버킷 (secure share)
# ==========================================
# media 와 완전히 분리된 팀 내부 중요정보 공유 전용 비공개 버킷.
# ec2-role 에 "일부러" 연결하지 않는다(app iam.tf 주석 참고).
# force_destroy = false 라 비어 있지 않으면 destroy 가 BucketNotEmpty 로 막힌다.
resource "aws_s3_bucket" "secure_share" {
  bucket        = var.secure_share_bucket_name
  force_destroy = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "secure_share" {
  bucket = aws_s3_bucket.secure_share.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "secure_share" {
  bucket = aws_s3_bucket.secure_share.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "secure_share" {
  bucket = aws_s3_bucket.secure_share.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "secure_share" {
  bucket = aws_s3_bucket.secure_share.id

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "secure_share_tls_only" {
  bucket = aws_s3_bucket.secure_share.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.secure_share.arn,
        "${aws_s3_bucket.secure_share.arn}/*"
      ]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })
}
