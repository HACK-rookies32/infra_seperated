# ==========================================
# 3. IAM Role (SSM + S3 + Lambda) — app 스택
# ==========================================
# EC2 인스턴스 역할은 컴퓨팅과 함께 뜨고 내려가므로 app 에 둔다. 참조하는
# 버킷/파라미터는 base 에 있어 remote_state output 으로 잡는다.

resource "aws_iam_role" "ec2_role" {
  name = "kidhackapp-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_policy" "s3_access" {
  name = "kidhackapp-s3-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ]
      Resource = [
        local.base.media_bucket_arn,
        "${local.base.media_bucket_arn}/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "s3_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.s3_access.arn
}

# EC2 가 부팅 시 비밀 값을 SSM 에서 읽어가기 위한 권한. base 의 파라미터 7 개로
# 범위를 좁힌다. (원본 iam.tf 주석 참고)
resource "aws_iam_policy" "ssm_params" {
  name = "kidhackapp-ssm-params-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = [
          local.base.ssm_param_arns.db_password,
          local.base.ssm_param_arns.docdb_password,
          local.base.ssm_param_arns.jwt_secret,
          local.base.ssm_param_arns.dockerhub_token,
          local.base.ssm_param_arns.was_dockerhub_token,
          local.base.ssm_param_arns.firebase_key,
          local.base.ssm_param_arns.card_storage_key,
        ]
      },
      {
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ssm.${var.aws_region}.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_params_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ssm_params.arn
}

# EC2 인스턴스가 Lambda 코드를 갱신·호출할 수 있게 한다.
# ⚠️ 의도된 권한 상승 경로(원본 iam.tf 주석 참고). Resource = "*".
resource "aws_iam_policy" "lambda_deploy" {
  name = "kidhackapp-lambda-deploy-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "lambda:UpdateFunctionCode",
        "lambda:InvokeFunction",
        "lambda:ListFunctions"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_deploy_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.lambda_deploy.arn
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "kidhackapp-ec2-profile"
  role = aws_iam_role.ec2_role.name
}
