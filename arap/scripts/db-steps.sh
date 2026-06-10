#!/bin/bash
# arap DB 步骤（对标公司 create_db.sh + dbtools diff + check_db_buildtime）
# 所有 PG 操作通过 docker run postgres:16 连 host.docker.internal:5432（compose 里的 postgres 容器）。
set -euo pipefail

RESULT="${WORKSPACE:?}/result"
DB_DIR="${RESULT}/db"
PGIMAGE="postgres:16"
PGHOST="host.docker.internal"
PGPORT="5432"
PGUSER="postgres"
PGPASS="123"

PSQL() {
  docker run -i --rm --add-host=host.docker.internal:host-gateway \
    -e PGPASSWORD="${PGPASS}" "${PGIMAGE}" \
    psql -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -v ON_ERROR_STOP=1 "$@"
}
PGDUMP() {
  docker run -i --rm --add-host=host.docker.internal:host-gateway \
    -e PGPASSWORD="${PGPASS}" "${PGIMAGE}" \
    pg_dump -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" "$@"
}
db_exists() { [ "$(PSQL -tAc "SELECT 1 FROM pg_database WHERE datname='$1'" | tr -d '[:space:]')" = "1" ]; }

case "${1:?用法: db-steps.sh <createTestDb|dumpBase|genUpgrade>}" in
  createTestDb)
    echo "==> [执行数据] 建临时库 testapp 并灌 schema+data+upgrade"
    PSQL -c "DROP DATABASE IF EXISTS testapp;"
    PSQL -c "CREATE DATABASE testapp;"
    cat "${DB_DIR}/schema.sql" "${DB_DIR}/data.sql" $(ls "${DB_DIR}"/upgrade/V*.sql 2>/dev/null | sort) \
      | PSQL -d testapp -f -
    echo -n "  testapp 当前 schema seq = "; PSQL -d testapp -tAc "SELECT max(seq) FROM meta_schema_version"
    ;;

  dumpBase)
    echo "==> [出基准库] pg_dump testapp -> base.dump"
    PGDUMP -Fc testapp > "${DB_DIR}/base.dump"
    ls -l "${DB_DIR}/base.dump"
    ;;

  genUpgrade)
    echo "==> [对比数据] 对比目标环境库 arap_target，生成增量升级 SQL"
    out="${DB_DIR}/upgrade.sql"; : > "${out}"
    if db_exists arap_target; then
      cur=$(PSQL -d arap_target -tAc "SELECT coalesce(max(seq),0) FROM meta_schema_version" 2>/dev/null | tr -d '[:space:]')
      [ -n "${cur}" ] || cur=0
      echo "  目标库已存在，当前 seq=${cur}，仅生成增量"
      base="${cur}"
    else
      echo "  目标库不存在，生成全量（schema+data）"
      cat "${DB_DIR}/schema.sql" "${DB_DIR}/data.sql" >> "${out}"
      base=1
    fi
    for f in $(ls "${DB_DIR}"/upgrade/V*.sql 2>/dev/null | sort); do
      n=$(basename "$f" | sed 's/^V\([0-9]\{1,\}\)__.*/\1/')
      if [ "${n}" -gt "${base}" ]; then
        echo "  + 纳入 $(basename "$f")"
        cat "$f" >> "${out}"
      fi
    done
    echo "==> 升级 SQL 生成完毕: ${out}"
    echo "-------- upgrade.sql --------"; cat "${out}"; echo "----------------------------"
    ;;

  *)
    echo "未知 db 步骤: $1"; exit 1 ;;
esac
