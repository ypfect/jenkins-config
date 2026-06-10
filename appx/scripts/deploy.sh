#!/bin/bash
set -e

CONTAINER_NAME="${BUILD_SERVICE:-appx}-app"
HOST_PORT="8800"
CONTAINER_PORT="18080"

echo "==> 部署 ${BUILD_SERVICE:-appx} Env=${Env:-local} deployID=${deployID:-}"
echo "==> 拉取镜像: ${IMAGE}"
docker pull "${IMAGE}"

echo "==> 停止并删除旧容器（若存在）"
docker stop "${CONTAINER_NAME}" 2>/dev/null || true
docker rm "${CONTAINER_NAME}" 2>/dev/null || true

echo "==> 启动新容器: ${CONTAINER_NAME} (port ${HOST_PORT})"
docker run -d \
  --name "${CONTAINER_NAME}" \
  --restart unless-stopped \
  -p "${HOST_PORT}:${CONTAINER_PORT}" \
  "${IMAGE}"

echo "==> 等待服务就绪"
sleep 8

if docker inspect --format='{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null | grep -q true; then
  echo "容器运行中: http://localhost:${HOST_PORT}/"
  docker logs --tail 5 "${CONTAINER_NAME}"
  exit 0
fi

echo "ERROR: 容器未正常运行"
docker logs --tail 30 "${CONTAINER_NAME}"
exit 1
