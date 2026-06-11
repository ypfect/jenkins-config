#!/bin/bash
# 本地 fallback：Nexus 不可用时，用 mock-modules 产出 apps_src/result/（形态对标 build3.py）
set -euo pipefail

WORKSPACE="${WORKSPACE:?}"
PIPELINE="${WORKSPACE}/pipeline/appx"
SETTINGS="${PIPELINE}/maven/settings.xml"
CONFIG="${PIPELINE}/config.yaml"
MODSRC="${PIPELINE}/mock-modules"
APPS_SRC="${WORKSPACE}/apps_src"
RESULT="${APPS_SRC}/result"
WORK="${WORKSPACE}/appx-build"

M2="${MAVEN_REPO:-/root/.m2/repository}"
GROUP="com.demo"
DEP="org.apache.maven.plugins:maven-dependency-plugin:3.6.1"
MVN="mvn -B -s ${SETTINGS} -Dmaven.repo.local=${M2}"

rm -rf "${RESULT}" "${WORK}"
mkdir -p "${RESULT}" "${WORK}/META-INF/appx-modules"

APPX_VER=$(awk '/^mono:/{f=1;next} f && $1=="appx:"{print $2; exit}' "${CONFIG}")
MODULES=$(awk '/^modules:/{f=1;next} f && /^[^[:space:]]/{f=0} f && NF==2{gsub(":","",$1);print $1"="$2}' "${CONFIG}")
echo "==> [local fallback] appx=${APPX_VER} modules=${MODULES}"

${MVN} -q -f "${MODSRC}/appx/pom.xml" clean install -DskipTests
for kv in ${MODULES}; do
  name="${kv%%=*}"
  ${MVN} -q -f "${MODSRC}/${name}/pom.xml" clean install -DskipTests
done

${MVN} ${DEP}:unpack -Dsilent=true -Dartifact="${GROUP}:appx:${APPX_VER}" -DoutputDirectory="${WORK}"
for kv in ${MODULES}; do
  name="${kv%%=*}"; ver="${kv##*=}"
  tmp="${WORKSPACE}/tmp-${name}"; rm -rf "${tmp}"; mkdir -p "${tmp}"
  ${MVN} ${DEP}:unpack -Dsilent=true -Dartifact="${GROUP}:${name}:${ver}" -DoutputDirectory="${tmp}"
  cp -Rf "${tmp}"/* "${WORK}/"
done

cat "${WORK}/META-INF/appx-modules/"* > "${WORK}/META-INF/appx-modules.list"
cp "${CONFIG}" "${WORK}/config.yaml"
( cd "${WORK}" && jar cfe "${RESULT}/appx-${APPX_VER}.jar" com.demo.appx.AppxApplication . )
cp "${RESULT}/appx-${APPX_VER}.jar" "${RESULT}/app.jar"
cp "${PIPELINE}/Dockerfile" "${RESULT}/Dockerfile"
mkdir -p "${RESULT}/dbtools"
chown -R 1000:1000 "${RESULT}" "${WORK}" 2>/dev/null || true
echo "==> fallback 产物 apps_src/result/:"
ls -l "${RESULT}"
