# ============================================================================
# base 를 내리되 Oracle/DocDB 데이터는 final 스냅샷으로 남긴다.
# ----------------------------------------------------------------------------
# 사용법 (base/ 에서, TF_VAR_* 시크릿을 넣어 둔 셸로):
#   .\scripts\destroy-keep-db.ps1            # terraform destroy 확인 프롬프트가 뜬다
#   .\scripts\destroy-keep-db.ps1 -auto-approve
#
# 하는 일:
#   1. state 상 Oracle/DocDB 가 final 스냅샷을 남기게 되어 있는지 확인
#      (destroy 는 config 가 아니라 state 값을 쓰므로, apply 안 했으면 여기서 멈춘다)
#   2. 카드 암호화 키를 Terraform 밖의 SSM 파라미터로 복사 (복원 때 사용)
#   3. Oracle 옵션그룹을 state 에서 뺀다 — final 스냅샷이 붙잡고 있어 삭제가 안 되므로
#      AWS 에 남겨 두고, 복원 apply 때 import 블록이 다시 가져온다
#   4. terraform destroy (실패/취소 시 옵션그룹을 다시 import 해 원상복구)
#
# 복원: $env:TF_VAR_restore_from_snapshot = 'true'; terraform apply
# ============================================================================

$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$LiveKeyParam   = '/kidhackapp/app/card-storage-key'
$BackupKeyParam = if ($env:TF_VAR_card_storage_key_backup_param) { $env:TF_VAR_card_storage_key_backup_param } else { '/kidhackapp/backup/card-storage-key' }
$OptionGroup    = 'kidhackapp-oracle-options'

function Assert-FinalSnapshot([string]$Address) {
    $out = terraform state show -no-color $Address
    if ($LASTEXITCODE -ne 0) { throw "$Address 를 state 에서 찾지 못했습니다." }
    if (-not ($out -match '^\s*skip_final_snapshot\s*=\s*false\s*$')) {
        throw "$Address 의 state 가 skip_final_snapshot=false 가 아닙니다. keep_final_snapshot=true 로 먼저 'terraform apply' 하세요."
    }
    $id = ($out -match '^\s*final_snapshot_identifier\s*=') -replace '.*=\s*"?([^"]*)"?\s*$', '$1'
    Write-Host "  $Address -> final 스냅샷: $id"
}

Write-Host '[1/4] final 스냅샷 설정 확인'
Assert-FinalSnapshot 'aws_db_instance.oracle'
Assert-FinalSnapshot 'aws_docdb_cluster.mongo'

Write-Host "[2/4] 카드 암호화 키 백업 -> $BackupKeyParam"
$key = aws ssm get-parameter --name $LiveKeyParam --with-decryption --query Parameter.Value --output text
if ($LASTEXITCODE -ne 0 -or -not $key) { throw "$LiveKeyParam 를 읽지 못했습니다." }

# 백업 파라미터가 아직 없으면 ParameterNotFound 가 stderr 로 나온다. PS 5.1 은
# Stop 상태에서 리다이렉트된 stderr 를 예외로 바꾸므로 이 호출만 Continue 로 둔다.
$ErrorActionPreference = 'Continue'
$prev = aws ssm get-parameter --name $BackupKeyParam --with-decryption --query Parameter.Value --output text 2>$null
$prevExit = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($prevExit -eq 0 -and $prev -and $prev -ne $key) {
    Write-Warning "기존 백업 키와 현재 키가 다릅니다. 현재 키로 덮어씁니다(이번 스냅샷은 현재 키로 암호화돼 있음)."
}
aws ssm put-parameter --name $BackupKeyParam --type SecureString --overwrite --value $key `
    --description 'Backup of card-storage-key for snapshot restore (not managed by Terraform)' | Out-Null
if ($LASTEXITCODE -ne 0) { throw '백업 키 저장 실패' }
$check = aws ssm get-parameter --name $BackupKeyParam --with-decryption --query Parameter.Value --output text
if ($check -ne $key) { throw '백업 키 검증 실패 — destroy 를 중단합니다.' }
Write-Host '  백업 확인 완료'

Write-Host '[3/4] Oracle 옵션그룹을 state 에서 분리 (AWS 에는 남김)'
$inState = terraform state list | Where-Object { $_ -eq 'aws_db_option_group.oracle' }
if ($inState) {
    terraform state rm aws_db_option_group.oracle | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'state rm 실패' }
}

Write-Host '[4/4] terraform destroy'
terraform destroy @args
$destroyExit = $LASTEXITCODE

if ($destroyExit -ne 0) {
    $dbLeft = terraform state list | Where-Object { $_ -eq 'aws_db_instance.oracle' }
    if ($dbLeft) {
        Write-Warning 'destroy 가 취소/실패해 DB 가 남아 있습니다. 옵션그룹을 state 로 되돌립니다.'
        terraform import aws_db_option_group.oracle $OptionGroup
    }
    exit $destroyExit
}

Write-Host ''
Write-Host '완료. 남은 것: Oracle/DocDB final 스냅샷, 옵션그룹, 백업 키 파라미터.'
Write-Host "복원: `$env:TF_VAR_restore_from_snapshot = 'true'; terraform apply"
