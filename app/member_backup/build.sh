#!/usr/bin/env bash
# member 백업 Lambda zip 빌드 → app/member_backup.zip
#
# Lambda 는 Linux x86_64 / python3.12 이므로, 로컬 OS 와 무관하게 해당 플랫폼용
# oracledb 휠을 받는다. boto3 는 Lambda 런타임에 내장이라 넣지 않는다.
#   사용: bash app/member_backup/build.sh
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_ZIP="$SRC_DIR/../member_backup.zip"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

PYTHON="${PYTHON:-python}"

"$PYTHON" -m pip install \
  --quiet \
  --target "$BUILD_DIR" \
  --platform manylinux2014_x86_64 \
  --implementation cp \
  --python-version 3.12 \
  --only-binary=:all: \
  oracledb

# 로컬 pip 가 남기는 콘솔 스크립트(bin/)와 로컬 버전 바이트코드는 Lambda 에서 안 쓴다.
rm -rf "$BUILD_DIR/bin"
find "$BUILD_DIR" -name __pycache__ -type d -prune -exec rm -rf {} +

cp "$SRC_DIR/index.py" "$BUILD_DIR/"

rm -f "$OUT_ZIP"
(cd "$BUILD_DIR" && "$PYTHON" -m zipfile -c "$OUT_ZIP" ./*)

echo "built: $OUT_ZIP"
