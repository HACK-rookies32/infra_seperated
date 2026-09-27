# ==========================================
# 9. DNS (Route 53) — app 스택 (도메인 -> ALB Alias)
# ==========================================
# ACM 인증서 발급·검증은 base 가 끝내 둔다. 여기서는 도메인/ www 를 이번 app 의
# ALB 로 가리키는 Alias 레코드만 만든다. app destroy 시 이 레코드만 사라지고
# 호스팅 존·인증서는 base 에 남는다.

locals {
  cert_domains = var.domain_name != "" ? [
    var.domain_name,
    "www.${var.domain_name}",
  ] : []
}

resource "aws_route53_record" "alias" {
  for_each = toset(local.cert_domains)

  zone_id = local.base.route53_zone_id
  name    = each.key
  type    = "A"

  alias {
    name                   = aws_lb.ext_alb.dns_name
    zone_id                = aws_lb.ext_alb.zone_id
    evaluate_target_health = true
  }
}
