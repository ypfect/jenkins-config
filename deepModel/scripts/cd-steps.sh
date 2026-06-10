#!/bin/bash
# CD 步骤路由
set -euo pipefail

MODULE="${1:?用法: cd-steps.sh <module>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "${SCRIPT_DIR}/lib.sh"

case "${MODULE}" in
  logInit)
    echo "=== deepModel CD ==="
    echo "Env=${Env:-local}  deployID=${deployID:-}  IMAGE=${IMAGE:-}"
    if [ -n "${CI_BUILD:-}" ]; then
      echo "CI_BUILD=${CI_BUILD}"
    fi
    ;;
  deploy)
    if [ -z "${IMAGE:-}" ]; then
      echo "ERROR: IMAGE 参数不能为空"
      exit 1
    fi
    chmod +x "${SCRIPT_DIR}/deploy.sh"
    IMAGE="${IMAGE}" Env="${Env:-local}" deployID="${deployID:-}" "${SCRIPT_DIR}/deploy.sh"
    ;;
  writeStatus)
    write_status "${STATUS:-SUCCESS}" "cd"
    ;;
  *)
    echo "未知 Module: ${MODULE}"
    echo "可用: logInit | deploy | writeStatus"
    exit 1
    ;;
esac
