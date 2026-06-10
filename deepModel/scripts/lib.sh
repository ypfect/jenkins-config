#!/bin/bash
# 公共函数：模拟公司 QiQiOps 的 writeStatus 回调

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
  "job": "${job_type}",
  "status": "${status}",
  "buildNumber": "${BUILD_NUMBER:-}",
  "branch": "${BRANCH:-}",
  "image": "${IMAGE:-}",
  "timestamp": "$(date -Iseconds)"
}
EOF
  echo "==> 状态已记录: ${file}"
  cat "${file}"
}
