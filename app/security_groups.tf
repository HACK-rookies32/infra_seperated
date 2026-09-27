# ==========================================
# 2. Security Groups — app 스택
# ==========================================
# ext_alb / web / was SG 는 컴퓨팅과 함께 뜨고 내려가므로 app 에 둔다.
# DB 계층 SG(rds/docdb/redis)는 base 에 골격만 있고, "was_sg 로부터의 인그레스"는
# 여기서 standalone 규칙으로 base SG id 를 잡아 붙인다(base->app 역의존 회피).

locals {
  bastion_cidrs = ["192.168.0.0/24"] # base network 의 public_2a
  # base 의 web_private 서브넷 대역. was_sg 8080 인그레스 소스.
  # ⚠️ base 의 vpc_cidr/서브넷 대역을 바꾸면 이 값도 함께 고쳐야 한다(원본 주석 참고).
  web_private_cidrs = ["192.168.10.0/24", "192.168.11.0/24"]
}

resource "aws_security_group" "ext_alb_sg" {
  name   = "kidhackapp-ext-alb-sg"
  vpc_id = local.base.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "web_sg" {
  name   = "kidhackapp-web-sg"
  vpc_id = local.base.vpc_id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.ext_alb_sg.id]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = local.bastion_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "was_sg" {
  name   = "kidhackapp-was-sg"
  vpc_id = local.base.vpc_id

  # WEB EC2 요청 + NLB 헬스체크(둘 다 web_private 대역). 원본 주석 참고.
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = local.web_private_cidrs
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = local.bastion_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ------------------------------------------------------------------
# DB 계층 인그레스 — base SG 에 was_sg 소스로 붙인다(standalone).
# app destroy 시 이 규칙만 사라지고 base 의 DB·SG 골격은 남는다.
# ------------------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "rds_from_was" {
  security_group_id            = local.base.rds_sg_id
  referenced_security_group_id = aws_security_group.was_sg.id
  from_port                    = 1521
  to_port                      = 1521
  ip_protocol                  = "tcp"
  description                  = "WAS to Oracle 1521"
}

resource "aws_vpc_security_group_ingress_rule" "docdb_from_was" {
  security_group_id            = local.base.docdb_sg_id
  referenced_security_group_id = aws_security_group.was_sg.id
  from_port                    = 27017
  to_port                      = 27017
  ip_protocol                  = "tcp"
  description                  = "WAS to DocumentDB 27017"
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_was" {
  security_group_id            = local.base.redis_sg_id
  referenced_security_group_id = aws_security_group.was_sg.id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
  description                  = "WAS to Redis 6379"
}
