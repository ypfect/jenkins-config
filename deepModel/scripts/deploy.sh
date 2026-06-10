#!/bin/bash
set -e

CONTAINER_NAME="deepmodel-app"
HOST_PORT="18080"
CONTAINER_PORT="18080"

echo "==> 部署任务 Env=${Env:-local} deployID=${deployID:-}"
echo "==> 拉取镜像: ${IMAGE}"
docker pull "${IMAGE}"

echo "==> 停止并删除旧容器（若存在）"
docker stop "${CONTAINER_NAME}" 2>/dev/null || true
docker rm "${CONTAINER_NAME}" 2>/dev/null || true

echo "==> 启动新容器: ${CONTAINER_NAME}"
docker run -d \
  --name "${CONTAINER_NAME}" \
  --restart unless-stopped \
  -p "${HOST_PORT}:${CONTAINER_PORT}" \
  "${IMAGE}"

echo "==> 等待服务就绪（约 5~10 秒）"
sleep 8

if docker inspect --format='{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null | grep -q true; then
  echo "容器运行中，检查端口..."
  if docker exec "${CONTAINER_NAME}" curl -sf -o /dev/null http://localhost:${CONTAINER_PORT}/ 2>/dev/null || \
     docker exec "${CONTAINER_NAME}" wget -q -O /dev/null http://localhost:${CONTAINER_PORT}/ 2>/dev/null; then
    echo "服务已就绪: http://localhost:${HOST_PORT}/"
    exit 0
  fi
  echo "端口可能尚未就绪，再等 10 秒..."
  sleep 10
  if docker inspect --format='{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null | grep -q true; then
    echo "容器仍在运行，部署成功: http://localhost:${HOST_PORT}/"
    docker logs --tail 5 "${CONTAINER_NAME}"
    exit 0
  fi
fi

echo "ERROR: 容器未正常运行"
docker logs --tail 30 "${CONTAINER_NAME}"
exit 1
