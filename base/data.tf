# CloudTrail 버킷 정책(observability.tf)의 aws:SourceArn 조건에 계정 ID 가 필요하다.
data "aws_caller_identity" "current" {}
