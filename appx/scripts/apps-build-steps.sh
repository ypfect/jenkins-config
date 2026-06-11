#!/bin/bash
# 兼容旧调用：转发到 Python Module 路由
exec python3 -u "$(cd "$(dirname "$0")" && pwd)/apps-build-steps.py" "$@"
