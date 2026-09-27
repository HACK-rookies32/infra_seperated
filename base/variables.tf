# ============================================================================
# base 스택 변수
# ----------------------------------------------------------------------------
# base 는 "한 번 만들고 유지" 하는 계층이다: 네트워크 + DB + 시크릿/키 + 데이터
# 버킷. app 을 destroy/apply 해도 여기 있는 것들은 건드리지 않는다.
#
# ⚠️ default 가 없는 시크릿 변수(db_password 등)는 app 이 아니라 "base" 에만
#    필요하다. 즉 이 시크릿들은 base apply 때만 주입하면 된다. base 는 자주
#    바꾸지 않으므로 실제로 시크릿을 넣는 횟수가 크게 줄어든다.
# ============================================================================

variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "vpc_cidr" {
  type    = string
  default = "192.168.0.0/16"
}

variable "s3_bucket_name" {
  type    = string
  default = "kidhackapp-media-bucket-2026"
}

# 중요정보 공유용 프라이빗 버킷 이름 (storage.tf 의 secure_share).
# S3 버킷 이름은 전역 유일해야 하므로 충돌하면 이 값을 바꿀 것.
variable "secure_share_bucket_name" {
  type    = string
  default = "kidhackapp-secure-share-2026"
}

# CloudTrail 로그 전용 S3 버킷 이름. 이 버킷은 감사 로그와(백업 활성 시) member
# 월간 백업(3년 보관)을 담으므로 base 에 둔다 — app destroy 에 휩쓸리지 않는다.
variable "cloudtrail_bucket_name" {
  type    = string
  default = "kidhackapp-cloudtrail-logs-2026"
}

variable "cloudtrail_log_retention_days" {
  type    = number
  default = 90
}

# member 월간 백업(cloudtrail 버킷의 db-backup/ 접두) 보관 기간(일). 기본 3년.
variable "member_backup_retention_days" {
  type    = number
  default = 1095
}

variable "db_username" {
  type    = string
  default = "adminexample"
}

# RDS Oracle 마스터 비밀번호. default 없음 — 환경변수로 주입.
#   export TF_VAR_db_password='...'
# 제약: 8~30 자. / " @ & ' 와 공백 사용 불가.
variable "db_password" {
  type      = string
  sensitive = true
}

# destroy 시 최종 스냅샷을 남길지 여부.
# base 를 destroy 할 일은 거의 없지만, DB 리소스에 prevent_destroy 도 함께
# 걸려 있어(database.tf) 실수로 지워지지 않는다.
variable "keep_final_snapshot" {
  type    = bool
  default = false
}

variable "oracle_db_name" {
  type    = string
  default = "ORCL"
}

variable "docdb_username" {
  type    = string
  default = "docdbadmin"
}

# DocumentDB 마스터 비밀번호. default 없음 — 환경변수로 주입.
#   export TF_VAR_docdb_password='...'
# 제약: 8~100 자, / " @ 사용 불가.
variable "docdb_password" {
  type      = string
  sensitive = true
}

# 서비스 도메인. base 는 이 값으로 ACM 인증서를 발급·검증까지만 해 둔다
# (app 이 매번 재발급/재검증하며 기다리지 않도록). alias 레코드·443 리스너는 app.
variable "domain_name" {
  type    = string
  default = "kidhackapp.com"
}

# Firebase 서비스 계정 키(JSON 전문). SSM 에 저장(secrets.tf).
#   export TF_VAR_firebase_credentials_json="$(cat firebase-service-account.json)"
# 기본값 "{}" 는 "키 없음"(푸시 비활성).
variable "firebase_credentials_json" {
  type      = string
  sensitive = true
  default   = "{}"
}

# Docker Hub PAT (WEB). SSM 에 저장. default 없음 — 환경변수로 주입.
#   export TF_VAR_dockerhub_token='dckr_pat_...'
# ⚠️ Read-only 로 발급할 것.
variable "dockerhub_token" {
  type      = string
  sensitive = true
}

# Docker Hub PAT (WAS). 계정이 달라 별도 값. default 없음 — 환경변수로 주입.
#   export TF_VAR_was_dockerhub_token='dckr_pat_...'
variable "was_dockerhub_token" {
  type      = string
  sensitive = true
}
