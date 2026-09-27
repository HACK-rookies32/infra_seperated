output "alb_dns_name" {
  description = "ALB DNS name. Used directly when no domain is configured."
  value       = aws_lb.ext_alb.dns_name
}

output "route53_name_servers" {
  description = "Hosted zone NS records (base 에서 조회). 도메인 NS 와 일치해야 함."
  value       = local.base.route53_name_servers
}

output "service_url" {
  value = var.domain_name != "" ? "https://${var.domain_name}" : "http://${aws_lb.ext_alb.dns_name}"
}

output "internal_nlb_dns_name" {
  value = aws_lb.int_nlb.dns_name
}

# DB 엔드포인트는 base 소관 — 편의상 여기서도 노출.
output "redis_primary_endpoint" {
  value = local.base.redis_primary_endpoint
}

output "rds_endpoint" {
  value = local.base.rds_endpoint
}

output "docdb_cluster_endpoint" {
  value = local.base.docdb_cluster_endpoint
}

output "docdb_reader_endpoint" {
  value = local.base.docdb_reader_endpoint
}

output "ubuntu_ami_id" {
  description = "AMI currently in use. Pin this into var.ubuntu_ami_id before a demo."
  value       = local.ubuntu_ami
}

output "cloudtrail_name" {
  value = aws_cloudtrail.main.name
}

output "cloudtrail_s3_bucket" {
  value = local.base.cloudtrail_bucket_id
}

output "vpc_flow_log_group" {
  value = aws_cloudwatch_log_group.vpc_flow.name
}

output "ec2_log_groups" {
  value = { for k, g in aws_cloudwatch_log_group.ec2 : k => g.name }
}

output "secure_share_bucket" {
  value = local.base.secure_share_bucket
}

# ==========================================
# backend 레포의 GitHub Secret: APPLICATION_PROD_YML
# ==========================================
# 운영 프로파일 yml 을 인프라 값으로 렌더링한다(원본 outputs.tf 주석 참고).
# 엔드포인트/버킷은 base output 에서, 비밀은 여기 넣지 않고 $${...} 플레이스홀더로
# 남겨 WAS 부팅 스크립트가 app.env 로 채운다.
#
# 등록:
#   ( set -o pipefail
#     terraform output -raw backend_prod_yml | tr -d '\r' | base64 -w0 > /tmp/prod.b64 ) \
#     && test -s /tmp/prod.b64 \
#     && gh secret set APPLICATION_PROD_YML --repo HACK-rookies32/backend < /tmp/prod.b64
#   rm -f /tmp/prod.b64
output "backend_prod_yml" {
  description = "Renders application-prod.yml for the backend repo secret APPLICATION_PROD_YML"
  sensitive   = true
  value       = <<-YAML
    # 이 파일은 infra(app)의 `terraform output -raw backend_prod_yml` 이 생성한다.
    # 손으로 고치지 말 것 — 다음 등록 때 덮어써진다.
    spring:
      datasource:
        url: jdbc:oracle:thin:@//${local.base.rds_endpoint}/${var.oracle_db_name}
        username: ${var.db_username}
        password: $${SPRING_DATASOURCE_PASSWORD}
        driver-class-name: oracle.jdbc.OracleDriver
      jpa:
        database-platform: org.hibernate.dialect.OracleDialect
        hibernate:
          ddl-auto: validate
        show-sql: false
      flyway:
        enabled: true
      h2:
        console:
          enabled: false
      mongodb:
        uri: $${SPRING_DATA_MONGODB_URI}
      data:
        redis:
          host: ${local.base.redis_primary_endpoint}
          port: 6379
          ssl:
            enabled: true

    server:
      forward-headers-strategy: framework

    jwt:
      secret: $${JWT_SECRET}
      expiration: 3600000

    firebase:
      credentials-path: file:/run/secrets/firebase.json

    app:
      s3:
        bucket: ${local.base.media_bucket_id}
        prefix: uploads
        presign-ttl: 5m
      push:
        provider: firebase
      chat:
        broker: redis

    kidhack:
      card:
        storage-key: "$${CARD_STORAGE_KEY}"
  YAML
}
