# ============================================================================
# base outputs — app 스택이 terraform_remote_state 로 읽어간다.
# ============================================================================

# ---- 네트워크 ----
output "vpc_id" {
  value = aws_vpc.main.id
}

output "vpc_cidr_block" {
  value = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "[2a, 2c]"
  value       = [aws_subnet.public_2a.id, aws_subnet.public_2c.id]
}

output "web_private_subnet_ids" {
  description = "[2a, 2c]"
  value       = [aws_subnet.web_private_2a.id, aws_subnet.web_private_2c.id]
}

output "was_private_subnet_ids" {
  description = "[2a, 2c]"
  value       = [aws_subnet.was_private_2a.id, aws_subnet.was_private_2c.id]
}

# ---- DB 계층 보안 그룹 (app 이 인그레스를 붙인다) ----
output "rds_sg_id" {
  value = aws_security_group.rds_sg.id
}

output "docdb_sg_id" {
  value = aws_security_group.docdb_sg.id
}

output "redis_sg_id" {
  value = aws_security_group.redis_sg.id
}

# ---- DB 엔드포인트 ----
output "rds_endpoint" {
  value = aws_db_instance.oracle.endpoint
}

output "rds_address" {
  description = "RDS Oracle host only (백업 람다 접속용)"
  value       = aws_db_instance.oracle.address
}

output "docdb_cluster_endpoint" {
  value = aws_docdb_cluster.mongo.endpoint
}

output "docdb_reader_endpoint" {
  value = aws_docdb_cluster.mongo.reader_endpoint
}

output "redis_primary_endpoint" {
  value = aws_elasticache_replication_group.redis.primary_endpoint_address
}

# ---- 버킷 ----
output "media_bucket_id" {
  value = aws_s3_bucket.media.id
}

output "media_bucket_arn" {
  value = aws_s3_bucket.media.arn
}

output "secure_share_bucket" {
  value = aws_s3_bucket.secure_share.bucket
}

output "secure_share_bucket_arn" {
  value = aws_s3_bucket.secure_share.arn
}

output "cloudtrail_bucket_id" {
  value = aws_s3_bucket.cloudtrail.id
}

output "cloudtrail_bucket_arn" {
  value = aws_s3_bucket.cloudtrail.arn
}

# ---- SSM 파라미터 (app iam / user_data 가 이름·ARN 을 참조) ----
output "ssm_param_names" {
  value = {
    db_password         = aws_ssm_parameter.db_password.name
    docdb_password      = aws_ssm_parameter.docdb_password.name
    jwt_secret          = aws_ssm_parameter.jwt_secret.name
    dockerhub_token     = aws_ssm_parameter.dockerhub_token.name
    was_dockerhub_token = aws_ssm_parameter.was_dockerhub_token.name
    firebase_key        = aws_ssm_parameter.firebase_key.name
    card_storage_key    = aws_ssm_parameter.card_storage_key.name
  }
}

output "ssm_param_arns" {
  value = {
    db_password         = aws_ssm_parameter.db_password.arn
    docdb_password      = aws_ssm_parameter.docdb_password.arn
    jwt_secret          = aws_ssm_parameter.jwt_secret.arn
    dockerhub_token     = aws_ssm_parameter.dockerhub_token.arn
    was_dockerhub_token = aws_ssm_parameter.was_dockerhub_token.arn
    firebase_key        = aws_ssm_parameter.firebase_key.arn
    card_storage_key    = aws_ssm_parameter.card_storage_key.arn
  }
}

# ---- DNS / TLS ----
output "acm_certificate_arn" {
  description = "검증 완료된 인증서 ARN. domain_name 이 비어 있으면 \"\"."
  value       = var.domain_name != "" ? aws_acm_certificate_validation.cert[0].certificate_arn : ""
}

output "route53_zone_id" {
  value = var.domain_name != "" ? data.aws_route53_zone.main[0].zone_id : ""
}

output "route53_name_servers" {
  value = var.domain_name != "" ? data.aws_route53_zone.main[0].name_servers : []
}
