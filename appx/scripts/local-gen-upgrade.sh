#!/bin/bash
# 本地 mock genUpgradeScript：在 apps_src/result/dbtools/ 生成差量升级 SQL
set -euo pipefail

WORKSPACE="${WORKSPACE:?}"
APPS_SRC="${WORKSPACE}/apps_src"
DBTOOLS="${APPS_SRC}/result/dbtools"
ENV="${Env:-local}"
BUILD_DB="${BUILD_DB_NAME:-apps-build_local_main_0}"
BUILD_NO="${BUILD_NUMBER:-0}"

mkdir -p "${DBTOOLS}"
OUT="${DBTOOLS}/${BUILD_DB}_to_${ENV}.tenantallin-base.sql"
cat > "${OUT}" <<EOF
-- local mock genUpgradeScript（对标 dbtools diff 产物）
-- source: ${BUILD_DB}.tenant  target: ${ENV}.tenant-base
ALTER TABLE deploy_marker ADD COLUMN IF NOT EXISTS build_no text;
UPDATE deploy_marker SET build_no = '${BUILD_NO}', updated_at = now() WHERE id = 1;
EOF
echo "==> 已生成 ${OUT}"
