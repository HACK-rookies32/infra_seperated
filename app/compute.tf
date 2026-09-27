# ==========================================
# 6. Load Balancers & EC2 — app 스택
# ==========================================
# 서브넷/보안그룹(DB)/DB 엔드포인트/SSM 파라미터 이름/버킷/인증서는 base output 에서 온다.

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

locals {
  ubuntu_ami = var.ubuntu_ami_id != "" ? var.ubuntu_ami_id : data.aws_ami.ubuntu.id

  # IMDS 설정(원본 compute.tf 주석 참고). http_tokens=optional 은 실습용 의도.
  imds_v2 = {
    http_endpoint               = "enabled"
    http_tokens                 = "optional"
    http_put_response_hop_limit = 2
  }

  root_volume = {
    size      = 30
    type      = "gp3"
    encrypted = true
  }

  # EC2 서브넷 맵. base 의 서브넷 id 리스트를 for_each 키로 편다.
  web_subnets = {
    "1" = local.base.web_private_subnet_ids[0]
    "2" = local.base.web_private_subnet_ids[1]
  }
  was_subnets = {
    "1" = local.base.was_private_subnet_ids[0]
    "2" = local.base.was_private_subnet_ids[1]
  }

  # 컨테이너 안 nginx 가 NLB 이름을 재조회할 때 쓰는 VPC DNS(대역 + 2).
  vpc_dns = cidrhost(local.base.vpc_cidr_block, 2)

  web_user_data = templatefile("${path.module}/templates/web_user_data.sh.tftpl", {
    region                   = var.aws_region
    nlb_dns                  = aws_lb.int_nlb.dns_name
    dns_resolver             = local.vpc_dns
    timezone                 = var.timezone
    dockerhub_image          = var.dockerhub_image
    dockerhub_username       = var.dockerhub_username
    dockerhub_token_param    = local.base.ssm_param_names.dockerhub_token
    watchtower_image         = var.watchtower_image
    watchtower_poll_interval = var.watchtower_poll_interval

    docker_version   = var.docker_version
    authz_enabled    = var.enable_docker_authz_lab
    opa_authz_plugin = var.opa_authz_plugin
  })

  was_user_data = templatefile("${path.module}/templates/was_user_data.sh.tftpl", {
    region                 = var.aws_region
    docdb_endpoint         = local.base.docdb_cluster_endpoint
    docdb_username         = var.docdb_username
    timezone               = var.timezone
    db_password_param      = local.base.ssm_param_names.db_password
    docdb_password_param   = local.base.ssm_param_names.docdb_password
    jwt_secret_param       = local.base.ssm_param_names.jwt_secret
    firebase_key_param     = local.base.ssm_param_names.firebase_key
    card_storage_key_param = local.base.ssm_param_names.card_storage_key
    was_image              = var.was_image

    dockerhub_username    = var.was_dockerhub_username
    dockerhub_token_param = local.base.ssm_param_names.was_dockerhub_token

    watchtower_image         = var.watchtower_image
    watchtower_poll_interval = var.watchtower_poll_interval

    docker_version   = var.docker_version
    authz_enabled    = var.enable_docker_authz_lab
    opa_authz_plugin = var.opa_authz_plugin
  })
}

# WEB EC2 (2a, 2c)
resource "aws_instance" "web" {
  for_each = local.web_subnets

  ami                    = local.ubuntu_ami
  instance_type          = "t3.small"
  subnet_id              = each.value
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  key_name = var.ssh_key_name != "" ? var.ssh_key_name : null

  user_data_base64            = base64gzip(local.web_user_data)
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = local.imds_v2.http_endpoint
    http_tokens                 = local.imds_v2.http_tokens
    http_put_response_hop_limit = local.imds_v2.http_put_response_hop_limit
  }

  root_block_device {
    volume_size = local.root_volume.size
    volume_type = local.root_volume.type
    encrypted   = local.root_volume.encrypted
  }

  tags = { Name = "kidhackapp-web-${each.key}", App = "kidhackapp" }
}

# External ALB
resource "aws_lb" "ext_alb" {
  name               = "kidhackapp-ext-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ext_alb_sg.id]
  subnets            = local.base.public_subnet_ids

  idle_timeout = 300
}

resource "aws_lb_target_group" "web_tg" {
  name     = "kidhackapp-web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = local.base.vpc_id

  health_check {
    path                = "/healthz"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group_attachment" "web" {
  # 키는 static(local.web_subnets: "1"/"2")으로 두고, apply 뒤에야 정해지는 인스턴스
  # id 는 값 쪽에서 조회한다. for_each = aws_instance.web 로 두면 EC2 생성 전엔
  # 키를 못 정한다며 "Invalid for_each argument" 로 막힌다.
  for_each = local.web_subnets

  target_group_arn = aws_lb_target_group.web_tg.arn
  target_id        = aws_instance.web[each.key].id
  port             = 80
}

# ------------------------------------------------------------------
# ALB 리스너 (var.domain_name 유무로 자동 분기)
# ------------------------------------------------------------------
resource "aws_lb_listener" "http_forward" {
  count             = var.domain_name == "" ? 1 : 0
  load_balancer_arn = aws_lb.ext_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

resource "aws_lb_listener" "http_redirect" {
  count             = var.domain_name != "" ? 1 : 0
  load_balancer_arn = aws_lb.ext_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# 443 리스너 — 인증서 ARN 은 base 에서 검증 완료된 것을 가져온다.
resource "aws_lb_listener" "https" {
  count             = var.domain_name != "" ? 1 : 0
  load_balancer_arn = aws_lb.ext_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = local.base.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

# WAS EC2 (2a, 2c)
resource "aws_instance" "was" {
  for_each = local.was_subnets

  ami                    = local.ubuntu_ami
  instance_type          = "t3.medium"
  subnet_id              = each.value
  vpc_security_group_ids = [aws_security_group.was_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  key_name = var.ssh_key_name != "" ? var.ssh_key_name : null

  user_data_base64            = base64gzip(local.was_user_data)
  user_data_replace_on_change = true

  # DB 는 base 에 이미 있다. WAS 부팅 전에 DB 로 가는 SG 경로(인그레스)가 열려
  # 있도록 그 규칙에 의존시킨다(원본의 RDS/Redis depends_on 대체).
  depends_on = [
    aws_vpc_security_group_ingress_rule.rds_from_was,
    aws_vpc_security_group_ingress_rule.redis_from_was,
    aws_vpc_security_group_ingress_rule.docdb_from_was,
  ]

  metadata_options {
    http_endpoint               = local.imds_v2.http_endpoint
    http_tokens                 = local.imds_v2.http_tokens
    http_put_response_hop_limit = local.imds_v2.http_put_response_hop_limit
  }

  root_block_device {
    volume_size = local.root_volume.size
    volume_type = local.root_volume.type
    encrypted   = local.root_volume.encrypted
  }

  tags = { Name = "kidhackapp-was-${each.key}", App = "kidhackapp" }
}

# Internal NLB
resource "aws_lb" "int_nlb" {
  name               = "kidhackapp-int-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = local.base.web_private_subnet_ids

  enable_cross_zone_load_balancing = true
}

resource "aws_lb_target_group" "was_tg" {
  name     = "kidhackapp-was-tg"
  port     = 8080
  protocol = "TCP"
  vpc_id   = local.base.vpc_id

  # 원본 compute.tf 주석 참고(readiness 경로, NLB threshold 대칭 등).
  health_check {
    protocol            = "HTTP"
    port                = "8080"
    path                = "/actuator/health/readiness"
    matcher             = "200"
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group_attachment" "was" {
  # web 쪽과 동일한 이유로 키를 static 으로 (compute.tf 의 web 첨부 주석 참고).
  for_each = local.was_subnets

  target_group_arn = aws_lb_target_group.was_tg.arn
  target_id        = aws_instance.was[each.key].id
  port             = 8080
}

resource "aws_lb_listener" "nlb_tcp" {
  load_balancer_arn = aws_lb.int_nlb.arn
  port              = 8080
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.was_tg.arn
  }
}
