# ==========================================
# media 버킷 CORS — app 스택
# ==========================================
# 버킷 자체는 base 에 있지만, 허용 오리진이 ALB/도메인(app)에 의존하므로 CORS
# 설정만 app 에서 base 버킷 id 를 잡아 붙인다. app destroy 시 CORS 만 사라진다
# (WAS 가 없으면 브라우저 직접 업로드도 없으므로 무해).
locals {
  media_cors_origins = var.domain_name != "" ? [
    "https://${var.domain_name}",
    "https://www.${var.domain_name}",
    "https://${var.admin_subdomain}.${var.domain_name}",
    ] : [
    "http://${aws_lb.ext_alb.dns_name}",
  ]
}

resource "aws_s3_bucket_cors_configuration" "media" {
  bucket = local.base.media_bucket_id

  cors_rule {
    allowed_origins = local.media_cors_origins
    allowed_methods = ["PUT", "GET", "HEAD"]
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}
