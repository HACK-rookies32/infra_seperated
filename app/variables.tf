# ============================================================================
# app 스택 변수
# ----------------------------------------------------------------------------
# app 은 "apply/destroy 를 반복" 하는 계층이다: 컴퓨팅(EC2)·로드밸런서·EC2 IAM·
# 관측 파이프라인·(옵션)백업 람다. DB/네트워크/시크릿/데이터 버킷은 base 에 있다.
#
# ✅ app 에는 default 없는 시크릿 변수가 없다. DB/Docker/Firebase 시크릿은 전부
#    base 에서 소비되므로, app apply/destroy 시 시크릿 환경변수를 넣을 필요가 없다.
# ============================================================================

variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

# base 원격 상태 파일 위치 (data.tf 의 terraform_remote_state 가 읽는다).
# 기본값은 "../base/terraform.tfstate" 로컬 경로. S3 백엔드로 옮기면 여기 대신
# data.tf 의 backend 설정을 바꾼다.
variable "base_state_path" {
  type    = string
  default = "../base/terraform.tfstate"
}

# 서비스 도메인. base 와 같은 값을 써야 한다(alias 레코드/443 리스너 분기).
variable "domain_name" {
  type    = string
  default = "kidhackapp.com"
}

# 관리자 콘솔 서브도메인 라벨. manage.<domain_name> 으로만 관리자 SPA 가 뜬다
# (호스트 분기는 웹 이미지의 nginx 가 ADMIN_HOST env 로 한다).
variable "admin_subdomain" {
  type    = string
  default = "manage"
}

# backend_prod_yml 렌더링·WAS user_data 에 쓰는 DB 좌표(값 아님, 이름/계정만).
variable "oracle_db_name" {
  type    = string
  default = "ORCL"
}

variable "db_username" {
  type    = string
  default = "adminexample"
}

variable "docdb_username" {
  type    = string
  default = "docdbadmin"
}

# ---- EC2 / 이미지 ----
variable "ubuntu_ami_id" {
  type    = string
  default = ""
}

variable "docker_version" {
  type    = string
  default = "29.3.0"
}

variable "dockerhub_image" {
  type    = string
  default = "bulletbear/kidhack-web"
}

variable "was_image" {
  type    = string
  default = "jotriever/kidhack-was"
}

variable "dockerhub_username" {
  type    = string
  default = "bulletbear"
}

variable "was_dockerhub_username" {
  type    = string
  default = "jotriever"
}

variable "watchtower_image" {
  type    = string
  default = "nickfedor/watchtower:1.21.2"
}

variable "watchtower_poll_interval" {
  type    = number
  default = 300
}

variable "timezone" {
  type    = string
  default = "Asia/Seoul"
}

variable "ssh_key_name" {
  type    = string
  default = "kidhackapp-key"
}

# ---- 관측 (observability.tf) ----
variable "flow_log_retention_days" {
  type    = number
  default = 14
}

variable "ec2_log_retention_days" {
  type    = number
  default = 30
}

variable "enable_cloudwatch_agent" {
  type    = bool
  default = true
}

# ---- member 월간 백업 람다 (backup.tf, 기본 off) ----
variable "enable_member_backup" {
  description = "member 월간 백업 Lambda 생성 토글. false 면 아무것도 생성하지 않음."
  type        = bool
  default     = false
}

variable "member_backup_zip_path" {
  description = "백업 Lambda 핸들러 zip 경로(팀 제공). enable_member_backup=true 면 필수."
  type        = string
  default     = ""
}

variable "member_backup_handler" {
  type    = string
  default = "index.handler"
}

variable "member_backup_runtime" {
  type    = string
  default = "python3.12"
}

variable "member_backup_schedule" {
  description = "백업 트리거 EventBridge 스케줄 식. 기본: 매월 1일 KST 09:00."
  type        = string
  default     = "cron(0 0 1 * ? *)"
}

# ---- Docker AuthZ(OPA) 실습 토글 ----
variable "enable_docker_authz_lab" {
  description = "Docker AuthZ(OPA) 플러그인을 WEB/WAS 4대에 설치·배선하는 토글."
  type        = bool
  default     = true
}

variable "opa_authz_plugin" {
  type    = string
  default = "openpolicyagent/opa-docker-authz-v2:0.9"
}

variable "enable_deploy_helper" {   # (예시) 변수명
  description = "시나리오2 배포 헬퍼 Lambda(ELB/EC2 조작)와 실행 역할 생성 여부. 평소 false, 실습 시 true."
  type        = bool
  default     = true
}

variable "enable_ops_admin" {       # (예시) 변수명
  description = "시나리오2 상위 권한 자격(SSM 저장) 생성 여부. 평소 false."
  type        = bool
  default     = true
}

variable "deploy_helper_zip_path" { # (예시) 변수명
  description = "위 Lambda에 올릴 코드 zip 경로. 내용은 공격 시 교체되므로 빈 껍데기면 됨."
  type        = string
  default     = "./deploy_helper_stub.zip"
}