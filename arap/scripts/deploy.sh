#!/bin/bash
# arap 部署（对标公司：对目标环境库执行升级 SQL → 起服务）
set -e

CONTAINER_NAME="arap-app"
HOST_PORT="8801"
CONTAINER_PORT="8801"
PGIMAGE="postgres:16"
PGNET="${PG_NETWORK:-practice_default}"
PGHOST="${PG_HOST:-postgres}"
PGPORT="5432"
PGUSER="postgres"
PGPASS="123"
TARGET_DB="arap_target"

PSQL() {
  docker run -i --rm --network "${PGNET}" \
    -e PGPASSWORD="${PGPASS}" "${PGIMAGE}" \
    psql -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -v ON_ERROR_STOP=1 "$@"
}
db_exists() { [ "$(PSQL -tAc "SELECT 1 FROM pg_database WHERE datname='$1'" | tr -d '[:space:]')" = "1" ]; }

echo "==> 部署 arap Env=${Env:-local} deployID=${deployID:-}  IMAGE=${IMAGE}"
docker pull "${IMAGE}"

echo "==> 确保目标环境库 ${TARGET_DB} 存在"
if ! db_exists "${TARGET_DB}"; then
  PSQL -c "CREATE DATABASE \"${TARGET_DB}\";"
  echo "  已创建 ${TARGET_DB}"
fi

echo "==> [执行升级] 从镜像取出 upgrade.sql 并对 ${TARGET_DB} 执行"
cid=$(docker create "${IMAGE}")
docker cp "${cid}:/app/db/upgrade.sql" /tmp/arap-upgrade.sql
docker rm "${cid}" >/dev/null
if [ -s /tmp/arap-upgrade.sql ]; then
  cat /tmp/arap-upgrade.sql | PSQL -d "${TARGET_DB}" -f -
  echo "  升级 SQL 已执行"
else
  echo "  无增量升级（upgrade.sql 为空），跳过"
fi
echo -n "  ${TARGET_DB} 当前 schema seq = "; PSQL -d "${TARGET_DB}" -tAc "SELECT max(seq) FROM meta_schema_version"

echo "==> 启动服务容器 ${CONTAINER_NAME}"
docker stop "${CONTAINER_NAME}" 2>/dev/null || true
docker rm "${CONTAINER_NAME}" 2>/dev/null || true
docker run -d \
  --name "${CONTAINER_NAME}" \
  --restart unless-stopped \
  --network "${PGNET}" \
  -p "${HOST_PORT}:${CONTAINER_PORT}" \
  -e PGHOST="${PGHOST}" \
  -e PGDB="${TARGET_DB}" \
  "${IMAGE}"

echo "==> 等待服务就绪"
sleep 6
if docker inspect --format='{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null | grep -q true; then
  echo "容器运行中: http://localhost:${HOST_PORT}/"
  docker logs --tail 8 "${CONTAINER_NAME}"
  exit 0
fi
echo "ERROR: 容器未正常运行"
docker logs --tail 30 "${CONTAINER_NAME}"
exit 1
