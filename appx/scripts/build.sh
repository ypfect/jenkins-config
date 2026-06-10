#!/bin/bash
# appx 聚合构建（对标公司 apps/build/build3.py -a appx）
#
# 本质：按 config.yaml 版本清单，从 Maven 仓库拉取已发布的模块 jar，
#       解包 → 合并到主壳 → jar 命令重打包成一个 mono fat jar。
# 全程不编译业务源码；首段 install 仅用于在本地仓"模拟模块已发布到 Nexus"。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APPX_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"   # pipeline/appx
SETTINGS="${APPX_DIR}/maven/settings.xml"
CONFIG="${APPX_DIR}/config.yaml"
MODSRC="${APPX_DIR}/mock-modules"

M2="${MAVEN_REPO:-/root/.m2/repository}"
RESULT="${WORKSPACE:?}/result"
WORK="${WORKSPACE}/appx-build"
GROUP="com.demo"
DEP_PLUGIN="org.apache.maven.plugins:maven-dependency-plugin:3.6.1"
MVN="mvn -B -s ${SETTINGS} -Dmaven.repo.local=${M2}"

rm -rf "${RESULT}" "${WORK}"
mkdir -p "${RESULT}" "${WORK}/META-INF/appx-modules"

# 解析 config.yaml（不引 yq，用 awk）
APPX_VER=$(awk '/^mono:/{f=1;next} f && $1=="appx:"{print $2; exit}' "${CONFIG}")
MODULES=$(awk '/^modules:/{f=1;next} f && /^[^[:space:]]/{f=0} f && NF==2{gsub(":","",$1);print $1"="$2}' "${CONFIG}")
echo "==> appx 主壳版本: ${APPX_VER}"
echo "==> 模块清单:"; echo "${MODULES}"

# 1) 模拟"模块已发布到 Nexus"：install 主壳与各模块到本地 Maven 仓
echo "==> [模拟发布] install 主壳与模块到本地 Maven 仓"
${MVN} -q -f "${MODSRC}/appx/pom.xml" clean install -DskipTests
for kv in ${MODULES}; do
  name="${kv%%=*}"
  ${MVN} -q -f "${MODSRC}/${name}/pom.xml" clean install -DskipTests
done

# 2) 按清单拉主壳 + 模块的二进制 jar，解包后合并（对标 build3.py dependency:unpack + cp -Rf）
echo "==> 拉取主壳 appx:${APPX_VER} 并解包"
${MVN} ${DEP_PLUGIN}:unpack -Dsilent=true \
  -Dartifact="${GROUP}:appx:${APPX_VER}" -DoutputDirectory="${WORK}"

for kv in ${MODULES}; do
  name="${kv%%=*}"; ver="${kv##*=}"
  echo "==> 拉取模块 ${name}:${ver} 并合并到主壳"
  tmp="${WORKSPACE}/tmp-${name}"; rm -rf "${tmp}"; mkdir -p "${tmp}"
  ${MVN} ${DEP_PLUGIN}:unpack -Dsilent=true \
    -Dartifact="${GROUP}:${name}:${ver}" -DoutputDirectory="${tmp}"
  cp -Rf "${tmp}"/* "${WORK}/"
done

# 3) 合并各模块的清单碎片为单一聚合清单（对标 build3.py 合并 string-res / merge_aware）
cat "${WORK}/META-INF/appx-modules/"* > "${WORK}/META-INF/appx-modules.list"
echo "==> 聚合模块清单:"; cat "${WORK}/META-INF/appx-modules.list"

# 4) 把版本清单放进产物（对标 build3.py: cp config.yaml BOOT-INF/classes）
cp "${CONFIG}" "${WORK}/config.yaml"

# 5) 重打包成 mono jar（对标 build3.py: jar cfM0 result/appx-<ver>.jar *）
echo "==> 重打包 appx-${APPX_VER}.jar"
( cd "${WORK}" && jar cfe "${RESULT}/appx-${APPX_VER}.jar" com.demo.appx.AppxApplication . )
cp "${RESULT}/appx-${APPX_VER}.jar" "${RESULT}/app.jar"
cp "${APPX_DIR}/Dockerfile" "${RESULT}/Dockerfile"

# 6) 交回属主，便于 Jenkins(uid 1000) stash
chown -R 1000:1000 "${RESULT}" "${WORK}" 2>/dev/null || true

echo "==> 聚合完成:"
ls -l "${RESULT}"
