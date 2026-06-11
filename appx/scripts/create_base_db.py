#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
本地简化版 create_base_db.py（对标 ci2k8s/backend-build-image-tx/scripts/create_base_db.py）

用法:
  python3 create_base_db.py <db_config.json> <env> <result_dir> <tenant|identity>

用 result/tenant.dump 或 identity.dump 重建环境的 tenant-base / identity-base。
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

PGIMAGE = "postgres:16"
PGNET = "practice_default"


def psql(cfg: dict, *args: str) -> None:
    cmd = [
        "docker", "run", "-i", "--rm", "--network", PGNET,
        "-e", f"PGPASSWORD={cfg.get('pass', '123')}",
        PGIMAGE, "psql",
        "-h", cfg.get("host", "postgres"),
        "-p", str(cfg.get("port", "5432")),
        "-U", cfg.get("user", "postgres"),
        "-v", "ON_ERROR_STOP=1",
        *args,
    ]
    print(f"+ {' '.join(cmd)}")
    p = subprocess.run(cmd)
    if p.returncode != 0:
        sys.exit(p.returncode)


def pg_restore(cfg: dict, db: str, dump: Path) -> None:
    cmd = [
        "docker", "run", "-i", "--rm", "--network", PGNET,
        "-e", f"PGPASSWORD={cfg.get('pass', '123')}",
        "-v", f"{dump.parent}:/dumps:ro",
        PGIMAGE, "pg_restore",
        "-h", cfg.get("host", "postgres"),
        "-p", str(cfg.get("port", "5432")),
        "-U", cfg.get("user", "postgres"),
        "-d", db, "--clean", "--if-exists",
        f"/dumps/{dump.name}",
    ]
    print(f"+ pg_restore → {db} ← {dump.name}")
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        # pg_restore 对空库常有 warning，stderr 非空不一定失败
        print(p.stdout)
        if p.returncode > 1:
            print(p.stderr, file=sys.stderr)
            sys.exit(p.returncode)


def main() -> None:
    if len(sys.argv) != 5:
        print("用法: create_base_db.py <db_config.json> <env> <result_dir> <tenant|identity>", file=sys.stderr)
        sys.exit(1)
    db_file = Path(sys.argv[1]).resolve()
    env_name = sys.argv[2]
    result_dir = Path(sys.argv[3]).resolve()
    db_type = sys.argv[4]

    data = json.loads(db_file.read_text(encoding="utf-8"))
    cfg = data[env_name]
    target = "tenant-base" if db_type == "tenant" else "identity-base"
    dump = result_dir / f"{db_type}.dump"

    if not dump.is_file():
        print(f"WARN: 未找到 {dump}，用 pg_dump 从 tenant-demo1 生成临时 dump（本地 fallback）")
        fallback_src = "tenant-demo1" if db_type == "tenant" else "identity"
        tmp = result_dir / f"{db_type}.dump"
        cmd = [
            "docker", "run", "-i", "--rm", "--network", PGNET,
            "-e", f"PGPASSWORD={cfg.get('pass', '123')}",
            PGIMAGE, "pg_dump",
            "-h", cfg.get("host", "postgres"),
            "-p", str(cfg.get("port", "5432")),
            "-U", cfg.get("user", "postgres"),
            "-Fc", fallback_src,
        ]
        print(f"+ pg_dump {fallback_src} → {tmp}")
        with tmp.open("wb") as f:
            p = subprocess.run(cmd, stdout=f)
            if p.returncode != 0:
                sys.exit(p.returncode)
        dump = tmp

    print(f"--> 重建基准库 {target} env={env_name}")
    psql(cfg, "-c", f"SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '{target}' AND pid <> pg_backend_pid();")
    psql(cfg, "-c", f"DROP DATABASE IF EXISTS \"{target}\";")
    psql(cfg, "-c", f"CREATE DATABASE \"{target}\";")
    pg_restore(cfg, target, dump)
    print(f"重建基准库 {target} 成功")


if __name__ == "__main__":
    main()
