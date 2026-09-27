# ==========================================
# 9. DNS (Route 53) & TLS (ACM) — base 스택
# ==========================================
# ACM 인증서 발급·DNS 검증까지만 base 에서 한다. 이렇게 나누면 app 을
# destroy/apply 해도 인증서가 그대로 남아 매번 재발급·재검증(수 분)을 기다리지
# 않는다. 도메인 -> ALB Alias 레코드와 443 리스너는 app 스택에 있다.
#
# var.domain_name 이 비어 있으면 이 파일의 리소스는 하나도 생성되지 않는다.

locals {
  dns_enabled = var.domain_name != "" ? 1 : 0

  cert_domains = var.domain_name != "" ? [
    var.domain_name,
    "www.${var.domain_name}",
  ] : []
}

# 호스팅 존은 조회만 한다(생성하지 않음). 이유는 원본 dns.tf 주석 참고 —
# 존을 resource 로 두면 destroy 마다 NS 가 바뀌어 도메인이 죽는다.
data "aws_route53_zone" "main" {
  count        = local.dns_enabled
  name         = var.domain_name
  private_zone = false
}

resource "aws_acm_certificate" "cert" {
  count                     = local.dns_enabled
  domain_name               = var.domain_name
  subject_alternative_names = ["www.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = toset(local.cert_domains)

  zone_id         = data.aws_route53_zone.main[0].zone_id
  allow_overwrite = true
  ttl             = 60

  name = one([
    for dvo in aws_acm_certificate.cert[0].domain_validation_options :
    dvo.resource_record_name if dvo.domain_name == each.key
  ])
  type = one([
    for dvo in aws_acm_certificate.cert[0].domain_validation_options :
    dvo.resource_record_type if dvo.domain_name == each.key
  ])
  records = [one([
    for dvo in aws_acm_certificate.cert[0].domain_validation_options :
    dvo.resource_record_value if dvo.domain_name == each.key
  ])]
}

resource "aws_acm_certificate_validation" "cert" {
  count                   = local.dns_enabled
  certificate_arn         = aws_acm_certificate.cert[0].arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]

  timeouts {
    create = "60m"
  }
}
