#!/bin/bash
# 公共函数：模拟公司 QiQiOps 的 writeStatus / callbackLog

write_status() {
  local status="${1:?status required}"
  local job_type="${2:-ci}"
  local deploy_id="${deployID:-none}"
  local dir="/var/jenkins_home/deploy-status"
  local file="${dir}/${deploy_id}.json"

  mkdir -p "${dir}"
  cat > "${file}" <<EOF
{
  "deployID": "${deploy_id}",
  "env": "${Env:-local}",
  "service": "${BUILD_SERVICE:-appx}",
  "job": "${job_type}",
  "status": "${status}",
  "buildNumber": "${BUILD_NUMBER:-}",
  "branch": "${Branch:-}",
  "image": "${IMAGE:-}",
  "timestamp": "$(date -Iseconds)"
}
EOF
  echo "==> 状态已记录: ${file}"
  cat "${file}"
}

callback_log() {
  local msg="${LOG_INFO:-}"
  echo "[callbackLog] deployID=${deployID:-} Env=${Env:-local} ${msg}"
}
