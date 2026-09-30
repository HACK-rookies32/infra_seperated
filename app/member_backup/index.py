# member 테이블 월간 백업 Lambda (backup.tf 의 aws_lambda_function.member_backup)
#
# Oracle member 테이블을 읽어 JSON Lines(gzip)로 로그 버킷 db-backup/ 에 올린다.
# 컬럼은 SELECT * 가 아니라 BACKUP_COLUMNS 허용 목록으로만 뽑는다 — 테이블에
# 민감 컬럼이 새로 추가돼도 백업에 딸려 들어가지 않게 하기 위함이다.
#
# 제외 컬럼:
#   password — 비밀번호 해시. 복구 시엔 재설정으로 처리하면 되고, 백업 파일이
#              유출되면 오프라인 크래킹 대상이 되므로 저장하지 않는다.
#
# 환경변수(backup.tf 에서 주입):
#   DB_HOST, DB_PORT, DB_SID, DB_USER, DB_PASSWORD_PARAM, BACKUP_BUCKET, BACKUP_PREFIX

import datetime
import decimal
import gzip
import io
import json
import os

import boto3
import oracledb

BACKUP_COLUMNS = [
    "id",
    "login_id",
    "username",
    "nickname",
    "email",
    "phone_number",
    "birth_date",
    "address",
    "profile_image_url",
    "role",
    "parent_id",
    "is_deleted",
    "created_at",
    "updated_at",
]

FETCH_SIZE = 1000

ssm = boto3.client("ssm")
s3 = boto3.client("s3")


def _json_default(value):
    if isinstance(value, (datetime.datetime, datetime.date)):
        return value.isoformat()
    if isinstance(value, decimal.Decimal):
        return int(value) if value == value.to_integral_value() else str(value)
    raise TypeError(f"직렬화할 수 없는 타입: {type(value).__name__}")


def _db_password():
    resp = ssm.get_parameter(Name=os.environ["DB_PASSWORD_PARAM"], WithDecryption=True)
    return resp["Parameter"]["Value"]


def _connect():
    dsn = oracledb.makedsn(
        os.environ["DB_HOST"],
        int(os.environ.get("DB_PORT", "1521")),
        sid=os.environ["DB_SID"],
    )
    return oracledb.connect(user=os.environ["DB_USER"], password=_db_password(), dsn=dsn)


def _dump_members(conn):
    """member 행을 gzip 된 JSON Lines 로 메모리에 쓴다. (바이트, 행 수) 반환."""
    buf = io.BytesIO()
    rows = 0
    sql = f"SELECT {', '.join(BACKUP_COLUMNS)} FROM member ORDER BY id"

    with conn.cursor() as cur, gzip.GzipFile(fileobj=buf, mode="wb") as gz:
        cur.arraysize = FETCH_SIZE
        cur.execute(sql)
        while True:
            batch = cur.fetchmany()
            if not batch:
                break
            for row in batch:
                record = dict(zip(BACKUP_COLUMNS, row))
                line = json.dumps(record, ensure_ascii=False, default=_json_default)
                gz.write(line.encode("utf-8") + b"\n")
            rows += len(batch)

    return buf.getvalue(), rows


def handler(event, context):
    now = datetime.datetime.now(datetime.timezone.utc)
    prefix = os.environ.get("BACKUP_PREFIX", "db-backup/")
    key = f"{prefix}member/{now:%Y/%m}/member-{now:%Y%m%dT%H%M%SZ}.jsonl.gz"

    with _connect() as conn:
        body, rows = _dump_members(conn)

    s3.put_object(
        Bucket=os.environ["BACKUP_BUCKET"],
        Key=key,
        Body=body,
        ContentType="application/x-ndjson",
        ContentEncoding="gzip",
        ServerSideEncryption="AES256",
        Metadata={"row-count": str(rows), "columns": ",".join(BACKUP_COLUMNS)},
    )

    result = {"bucket": os.environ["BACKUP_BUCKET"], "key": key, "rows": rows, "bytes": len(body)}
    print(json.dumps(result))
    return result
