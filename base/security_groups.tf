# ==========================================
# DB 계층 보안 그룹 — base 스택
# ==========================================
# rds / docdb / redis SG 는 DB 인스턴스(database.tf)가 참조하므로 base 에 둔다.
#
# ⚠️ 인그레스(1521/27017/6379 <- was_sg)는 여기 두지 않는다.
#   인바운드 소스인 was_sg 는 app 스택에 있어, 여기서 참조하면 base 가 app 에
#   역으로 의존하게 된다(순환). 그래서 인그레스 규칙은 app 스택에서
#   aws_vpc_security_group_ingress_rule 로 이 SG 들의 id(base output)를 잡아 만든다.
#   app 을 destroy 하면 그 인그레스만 사라지고, DB 와 이 SG 골격은 남는다.
#
# ⚠️ 인라인 규칙을 아예 쓰지 않는다(egress 도 standalone). 한 SG 에 인라인과
#   standalone 을 섞으면 provider 가 서로의 규칙을 덮어쓰기 때문이다. app 이
#   인그레스를 standalone 으로 붙일 것이므로 여기 egress 도 standalone 으로 맞춘다.

resource "aws_security_group" "rds_sg" {
  name        = "kidhackapp-rds-sg"
  description = "Oracle RDS - ingress added from app stack"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "kidhackapp-rds-sg" }
}

resource "aws_vpc_security_group_egress_rule" "rds_all" {
  security_group_id = aws_security_group.rds_sg.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "docdb_sg" {
  name        = "kidhackapp-docdb-sg"
  description = "DocumentDB - ingress added from app stack"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "kidhackapp-docdb-sg" }
}

resource "aws_vpc_security_group_egress_rule" "docdb_all" {
  security_group_id = aws_security_group.docdb_sg.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "redis_sg" {
  name        = "kidhackapp-redis-sg"
  description = "ElastiCache Redis - ingress added from app stack"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "kidhackapp-redis-sg" }
}

resource "aws_vpc_security_group_egress_rule" "redis_all" {
  security_group_id = aws_security_group.redis_sg.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
