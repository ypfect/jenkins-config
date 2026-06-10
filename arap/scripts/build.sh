#!/bin/bash
# arap 聚合构建（对标公司 apps/build/build3.py：拉 jar + copy-dependencies 合并 → 重打包）
#
# 与 appx 不同：arap 业务源码来自独立 GitHub 仓（已 checkout 到 WORKSPACE 根），
# 这里先 install 到本地 m2 模拟"已发布到 Nexus"，再 unpack + 合并 JDBC 依赖后重打包。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CFG_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"     # pipeline/arap
SETTINGS="${CFG_DIR}/maven/settings.xml"
CONFIG="${CFG_DIR}/config.yaml"
SRC="${WORKSPACE:?}"                            # arap 业务仓 checkout 根
M2="${MAVEN_REPO:-/root/.m2/repository}"
RESULT="${WORKSPACE}/result"
WORK="${WORKSPACE}/arap-build"
GROUP="com.demo"
DEP="org.apache.maven.plugins:maven-dependency-plugin:3.6.1"
MVN="mvn -B -s ${SETTINGS} -Dmaven.repo.local=${M2}"

rm -rf "${RESULT}" "${WORK}"
mkdir -p "${RESULT}" "${WORK}"

ARAP_VER=$(awk '/^mono:/{f=1;next} f && $1=="arap:"{print $2; exit}' "${CONFIG}")
PG_VER=$(awk '/^deps:/{f=1;next} f && $1=="postgresql:"{print $2; exit}' "${CONFIG}")
echo "==> arap 版本: ${ARAP_VER}, postgresql: ${PG_VER}"

# 1) 模拟发布：install 业务仓到本地 m2
echo "==> [模拟发布] install arap 业务仓到本地 Maven 仓"
${MVN} -q -f "${SRC}/pom.xml" clean install -DskipTests

# 2) 拉 arap jar 并解包（对标 build3.py dependency:unpack）
echo "==> 拉取 arap:${ARAP_VER} 并解包"
${MVN} ${DEP}:unpack -Dsilent=true \
  -Dartifact="${GROUP}:arap:${ARAP_VER}" -DoutputDirectory="${WORK}"

# 3) copy-dependencies 拉 JDBC，合并进聚合目录（对标 build3.py copy-dependencies + 合并 lib）
echo "==> 拉取并合并 postgresql JDBC:${PG_VER}"
libtmp="${WORKSPACE}/lib-tmp"; rm -rf "${libtmp}"; mkdir -p "${libtmp}"
${MVN} ${DEP}:copy -Dsilent=true \
  -Dartifact="org.postgresql:postgresql:${PG_VER}" -DoutputDirectory="${libtmp}"
pgx="${WORKSPACE}/.pgx"; rm -rf "${pgx}"; mkdir -p "${pgx}"
( cd "${pgx}" && jar xf "$(ls "${libtmp}"/*.jar | head -1)" )
cp -rf "${pgx}/org" "${WORK}/"
mkdir -p "${WORK}/META-INF/services"
cp -rf "${pgx}/META-INF/services/." "${WORK}/META-INF/services/" 2>/dev/null || true
rm -rf "${libtmp}" "${pgx}"

# 4) 放入版本清单（对标 build3.py: cp config.yaml）
cp "${CONFIG}" "${WORK}/config.yaml"

# 5) 重打包成可运行 jar（对标 build3.py: jar cfM0 / cfe）
echo "==> 重打包 arap-${ARAP_VER}.jar"
( cd "${WORK}" && jar cfe "${RESULT}/arap-${ARAP_VER}.jar" com.demo.arap.ArapApplication . )
cp "${RESULT}/arap-${ARAP_VER}.jar" "${RESULT}/app.jar"

# 6) 带上 DB 脚本与 Dockerfile（供 db-steps 建库/对比 与 打镜像使用）
cp -rf "${SRC}/db" "${RESULT}/db"
cp "${CFG_DIR}/Dockerfile" "${RESULT}/Dockerfile"

chown -R 1000:1000 "${RESULT}" "${WORK}" 2>/dev/null || true
echo "==> 聚合完成:"
ls -lR "${RESULT}"
