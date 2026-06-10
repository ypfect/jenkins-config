#!/bin/bash
# arap CI/CD Module 路由（对标公司 apps-build-steps.py --Module=xxx）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
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
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

[ -n "${MODULE}" ] || { echo "用法: apps-build-steps.sh --Module=<name> [其它 --参数]"; exit 1; }

case "${MODULE}" in
  getAppx)
    echo "build apps = ['arap']"
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
  createTestDb|dumpBase|genUpgrade)
    bash "${SCRIPT_DIR}/db-steps.sh" "${MODULE}"
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
    echo "==> 镜像已推送: ${REGISTRY}/${IMAGE_NAME}:${BUILD_NUMBER}"
    ;;
  deploy)
    if [ -z "${IMAGE:-}" ]; then echo "ERROR: IMAGE 不能为空"; exit 1; fi
    chmod +x "${SCRIPT_DIR}/deploy.sh"
    IMAGE="${IMAGE}" Env="${Env:-local}" deployID="${deployID:-}" "${SCRIPT_DIR}/deploy.sh"
    ;;
  writeStatus)
    write_status "${STATUS:-SUCCESS}" "${JOB_TYPE:-ci}"
    ;;
  *)
    echo "未知 Module: ${MODULE}"
    echo "可用: getAppx | checkTask | callbackLog | build | createTestDb | dumpBase | genUpgrade | dockerBuild | dockerPush | deploy | writeStatus"
    exit 1
    ;;
esac
