#!/bin/bash
# appx CI/CD Module 路由（对标公司 apps-build-steps.py --Module=xxx）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MOCK_DB="${SCRIPT_DIR}/mock/db-config.local.json"

source "${SCRIPT_DIR}/lib.sh"

MODULE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --Module=*) MODULE="${1#--Module=}"; shift ;;
    --Env=*) export Env="${1#--Env=}"; shift ;;
    --Branch=*) export Branch="${1#--Branch=}"; shift ;;
    --deployID=*) export deployID="${1#--deployID=}"; shift ;;
    --taskStatus=*) export STATUS="${1#--taskStatus=}"; shift ;;
    --buildID=*) export BUILD_NUMBER="${1#--buildID=}"; shift ;;
    --log_info=*) export LOG_INFO="${1#--log_info=}"; shift ;;
    --CI_BUILD=*) export CI_BUILD="${1#--CI_BUILD=}"; shift ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

[ -n "${MODULE}" ] || { echo "用法: apps-build-steps.sh --Module=<name> [其它 --参数]"; exit 1; }

case "${MODULE}" in
  getAppx)
    export BUILD_SERVICE="${BUILD_SERVICE:-appx}"
    echo "BUILD_SERVICE=${BUILD_SERVICE}"
    echo "build apps = ['${BUILD_SERVICE}']"
    ;;
  getDbConfig)
    if [ ! -f "${MOCK_DB}" ]; then
      echo "ERROR: 未找到 mock db 配置 ${MOCK_DB}"
      exit 1
    fi
    cp "${MOCK_DB}" db-config.json
    echo "==> 已写入 db-config.json（mock getDbConfig）"
    cat db-config.json
    ;;
  checkTask)
    echo "==> checkTask OK（本地练习跳过互斥锁） Env=${Env:-local} Branch=${Branch:-main}"
    ;;
  callbackLog)
    callback_log
    ;;
  build)
    bash "${SCRIPT_DIR}/build.sh"
    ;;
  dockerBuild)
    docker build \
      -t "${REGISTRY}/${IMAGE_NAME}:${BUILD_NUMBER}" \
      -t "${REGISTRY}/${IMAGE_NAME}:latest" \
      result
    ;;
  dockerPush)
    docker push "${REGISTRY}/${IMAGE_NAME}:${BUILD_NUMBER}"
    docker push "${REGISTRY}/${IMAGE_NAME}:latest"
    export IMAGE="${REGISTRY}/${IMAGE_NAME}:${BUILD_NUMBER}"
    echo "==> 镜像已推送: ${IMAGE}"
    ;;
  deploy)
    if [ -z "${IMAGE:-}" ]; then
      echo "ERROR: IMAGE 参数不能为空"
      exit 1
    fi
    chmod +x "${SCRIPT_DIR}/deploy.sh"
    IMAGE="${IMAGE}" Env="${Env:-local}" deployID="${deployID:-}" BUILD_SERVICE="${BUILD_SERVICE:-appx}" \
      "${SCRIPT_DIR}/deploy.sh"
    ;;
  writeStatus)
    write_status "${STATUS:-SUCCESS}" "${JOB_TYPE:-ci}"
    ;;
  *)
    echo "未知 Module: ${MODULE}"
    echo "可用: getAppx | getDbConfig | checkTask | callbackLog | build | dockerBuild | dockerPush | deploy | writeStatus"
    exit 1
    ;;
esac
