# base / app 분리 — kidhackapp 인프라

기존 단일 Terraform 루트를 **두 스택**으로 나눴다. app 을 몇 번을 내렸다 올려도
DB·데이터·시크릿은 그대로 남는다.

```
infra/
├─ base/   ← 한 번 apply 하고 유지 (network + DB + 시크릿/키 + 데이터 버킷)
└─ app/    ← apply / destroy 반복 (EC2 + LB + EC2 IAM + 관측 + 백업 람다)
```

app 은 `terraform_remote_state` 로 base 의 output 을 읽어 쓴다. **base 를 먼저 apply.**

---

## 무엇이 어디로 갔나

| base (유지) | app (반복) |
|---|---|
| VPC·서브넷·IGW·NAT·라우팅·S3 엔드포인트 (network.tf) | EC2 WEB/WAS·ALB·NLB·타깃그룹·리스너 (compute.tf) |
| RDS Oracle / DocumentDB / ElastiCache + 서브넷그룹·옵션·파라미터그룹 (database.tf) | ext_alb/web/was SG + **DB SG 인그레스 규칙** (security_groups.tf) |
| DB 계층 SG **골격**(rds/docdb/redis, egress만) (security_groups.tf) | EC2 IAM 역할·정책·프로파일 (iam.tf) |
| SSM 시크릿 7종 + `random_password.jwt_secret` + `random_bytes.card_storage_key` (secrets.tf) | CloudTrail 트레일·VPC Flow Logs·EC2 CloudWatch Agent (observability.tf) |
| media·secure_share 버킷 (storage.tf) | media 버킷 CORS (storage_cors.tf) |
| CloudTrail 로그/백업 버킷 + 버킷 정책 (observability.tf) | 도메인→ALB Alias 레코드 (dns.tf) |
| ACM 인증서 발급·검증 (dns.tf) | member 월간 백업 람다 (backup.tf, 기본 off) |

### 왜 이렇게 나눴나 (핵심 3가지)

1. **`card_storage_key`·`jwt_secret`·DB 비밀번호를 base 에 뒀다.** app 에 두면
   apply 마다 재생성되어, `card_storage_key` 는 저장된 카드가 전부 복호 불가가 되고
   DB 비밀번호는 SSM 값과 실제 DB 가 어긋난다. base 에 있으면 절대 안 바뀐다.
2. **DB SG 인그레스를 app 으로 뺐다.** DB SG(base)가 was_sg(app)를 참조하면 base 가
   app 에 역의존해 순환이 된다. 그래서 base 에는 SG 골격(egress)만 두고,
   `WAS→DB 1521/27017/6379` 인그레스는 app 에서 standalone 규칙으로 붙인다.
   app destroy 시 이 규칙만 사라지고 DB 와 SG 골격은 남는다.
3. **ACM 인증서를 base 에 뒀다.** app 을 내렸다 올릴 때마다 인증서를 재발급·재검증
   (수 분 대기)하지 않도록. 도메인→ALB Alias 레코드만 app 에 있다.

---

## 실행 순서

### 0. base 시크릿 준비 (base apply 때만 필요)

app 에는 default 없는 시크릿 변수가 **없다**. 시크릿은 전부 base 에서만 쓴다.

```powershell
# base/ 에서 (PowerShell)
$env:TF_VAR_db_password        = '...'   # Oracle 마스터 (8~30자, / " @ & ' 공백 불가)
$env:TF_VAR_docdb_password     = '...'   # DocumentDB (8~100자, / " @ 불가)
$env:TF_VAR_dockerhub_token    = 'dckr_pat_...'   # WEB (read-only)
$env:TF_VAR_was_dockerhub_token= 'dckr_pat_...'   # WAS (read-only)
$env:TF_VAR_firebase_credentials_json = (Get-Content firebase-service-account.json -Raw)
```

### 1. base — 한 번 만들고 유지

```powershell
cd base
terraform init
terraform apply        # DB 3종 생성 — 여기서 시간이 걸린다(최초 1회)
```

### 2. app — 여기서부터 반복

```powershell
cd ../app
terraform init
terraform apply        # EC2/LB/관측 등. DB 는 base 것을 그대로 씀
# ... 실습/점검 후 정리 ...
terraform destroy      # DB 는 건드리지 않는다. 다음엔 apply 만 다시
```

> app 의 `base_state_path` 기본값은 `../base/terraform.tfstate` 다. 폴더 구조를
> 바꾸면 이 변수(또는 app/data.tf 의 backend 설정)를 맞춰라.

---

## 안 쓸 때 비용 줄이기

- **DB 는 destroy 하지 말고 중지한다** (스토리지 요금만 남는다):
  ```powershell
  aws rds stop-db-instance --db-instance-identifier kidhackapp-oracle-db
  aws docdb stop-db-cluster --db-cluster-identifier kidhackapp-docdb-cluster
  ```
  ⚠️ RDS/DocDB 중지는 **7일 뒤 자동 재기동**된다. ElastiCache 는 중지가 없다.
- **NAT Gateway 는 base 에 있어 app 을 내려도 계속 과금된다**(2대 ≈ 시간당 요금 + 데이터).
  비용이 더 중요하면 NAT 2개·EIP 2개·private 라우트테이블(2a/2c)을 app 으로 옮기면
  app destroy 때 함께 사라진다. 다만 S3 게이트웨이 엔드포인트가 private 라우트
  테이블을 참조하므로 엔드포인트–라우트테이블 연결을 `aws_vpc_endpoint_route_table_association`
  으로 분리해야 한다. 필요하면 이 부분도 만들어 줄 수 있다.

---

## base 를 정말 내려야 할 때 (안전장치 해제)

base 의 DB·버킷에는 3중 안전장치가 걸려 있다: `deletion_protection = true`,
`lifecycle { prevent_destroy = true }`, RDS/DocDB 최종 스냅샷(`keep_final_snapshot`).
평소 destroy 를 막기 위한 것이므로, 정말 내리려면:

1. database.tf 에서 각 DB 의 `deletion_protection = false` 로 바꾸고 `terraform apply`
2. database.tf / storage.tf / observability.tf 의 `prevent_destroy = true` → `false`
3. 데이터를 남기려면 `$env:TF_VAR_keep_final_snapshot = 'true'`
4. `terraform destroy`

---

## 기존에 이미 배포된 게 있다면 (state 이전)

첨부해 준 `terraform.tfstate` 는 리소스 0개(비어 있음)라, 지금은 **그냥 base→app
순서로 새로 apply 하면 된다** — 이전 작업 불필요.

만약 다른 곳에 살아 있는 통합 state 가 있다면, DB 를 재생성하지 않으려면
`terraform state mv` 로 리소스를 각 스택 state 로 옮긴 뒤 apply 해야 한다(그래야
Terraform 이 "이미 있음"으로 인식하고 만들지 않는다). 그 상황이면 현재 살아 있는
`terraform state list` 결과를 주면 정확한 이동 매핑을 만들어 주겠다.

---

## 검증 메모

- 이 샌드박스는 Terraform provider 레지스트리 접근이 막혀 `terraform plan` 을 돌리지
  못했다. 대신 확인한 것: (1) `terraform fmt` 파싱 통과(양쪽), (2) 원본 리소스
  115개가 하나도 누락 없이 분리됨(+ SG 인라인→standalone 전환으로 7개 규칙 추가),
  (3) app 이 참조하는 모든 `base` output 이 실제로 정의돼 있음, (4) base↔app 교차
  참조 없음.
- **로컬에서 `terraform init && terraform validate && terraform plan` 을 한 번씩
  돌려 최종 확인**할 것. lock 파일(.terraform.lock.hcl)은 원본을 양쪽에 복사해 뒀다.
