#!/bin/bash
# CI 步骤路由（对标公司 apps-build-steps.py --Module=xxx）
set -euo pipefail

MODULE="${1:?用法: ci-steps.sh <module>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# agent none 时顶层 environment 的 WORKSPACE 为 null，必须在 shell 运行时解析
PIPELINE_DIR="${WORKSPACE:?}/pipeline"
SETTINGS="${PIPELINE_DIR}/deepModel/maven/settings.xml"

source "${SCRIPT_DIR}/lib.sh"

case "${MODULE}" in
  logInit)
    echo "=== deepModel CI ==="
    echo "Env=${Env:-local}  deployID=${deployID:-}  Branch=${BRANCH:-main}"
    echo "Registry=${REGISTRY:-}  Job=#${BUILD_NUMBER:-}"
    ;;
  package)
    if [ ! -f "${SETTINGS}" ]; then
      echo "ERROR: 未找到 ${SETTINGS}，请确认 Init 阶段已 checkout pipeline"
      exit 1
    fi
    cp "${SETTINGS}" settings.xml
    mvn -B -s settings.xml -Dmaven.repo.local=/root/.m2/repository clean package -DskipTests
    chown -R 1000:1000 .
    ;;
  dockerBuild)
    docker build \
      -t "${REGISTRY}/${IMAGE_NAME}:${BUILD_NUMBER}" \
      -t "${REGISTRY}/${IMAGE_NAME}:latest" \
      .
    ;;
  dockerPush)
    docker push "${REGISTRY}/${IMAGE_NAME}:${BUILD_NUMBER}"
    docker push "${REGISTRY}/${IMAGE_NAME}:latest"
    export IMAGE="${REGISTRY}/${IMAGE_NAME}:${BUILD_NUMBER}"
    echo "==> 镜像已推送: ${IMAGE}"
    ;;
  writeStatus)
    write_status "${STATUS:-SUCCESS}" "ci"
    ;;
  *)
    echo "未知 Module: ${MODULE}"
    echo "可用: logInit | package | dockerBuild | dockerPush | writeStatus"
    exit 1
    ;;
esac
