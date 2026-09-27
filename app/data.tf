# ============================================================================
# base 스택 상태 참조 + 공용 data
# ============================================================================
# app 은 network/DB/시크릿/버킷을 base 에서 만들었다고 전제하고, 그 output 을
# 여기서 읽어 쓴다. base 를 먼저 apply 해 두어야 한다.
data "terraform_remote_state" "base" {
  backend = "local"
  config = {
    path = var.base_state_path
  }
}

data "aws_caller_identity" "current" {}

locals {
  # 매 참조를 짧게 쓰기 위한 별칭.
  base = data.terraform_remote_state.base.outputs
}
