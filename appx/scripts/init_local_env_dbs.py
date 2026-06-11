#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""初始化本地环境 PG：创建 dbList 中的库并灌 deploy_marker 种子表。"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

WORKSPACE = Path(os.environ.get("WORKSPACE", ".")).resolve()
DB_FILE = WORKSPACE / os.environ.get("DBFILES", "postgres.local-db-config.json")
ENV_NAME = os.environ.get("Env", "local")
PGNET = os.environ.get("PG_NETWORK", "practice_default")
PGIMAGE = "postgres:16"

SEED = """
CREATE TABLE IF NOT EXISTS deploy_marker (
  id serial PRIMARY KEY,
  phase text NOT NULL DEFAULT 'baseline',
  build_no text,
  updated_at timestamptz DEFAULT now()
);
INSERT INTO deploy_marker(phase)
SELECT 'baseline' WHERE NOT EXISTS (SELECT 1 FROM deploy_marker);
"""


def run_cmd(cmd: list[str], *, input_text: str | None = None) -> None:
    print("+", " ".join(cmd))
    p = subprocess.run(cmd, input=input_text, text=True, capture_output=True)
    if p.returncode != 0:
        print(p.stdout)
        print(p.stderr, file=sys.stderr)
        sys.exit(p.returncode)


def psql_admin(cfg: dict, sql: str) -> None:
    run_cmd([
        "docker", "run", "-i", "--rm", "--network", PGNET,
        "-e", f"PGPASSWORD={cfg.get('pass', '123')}",
        PGIMAGE, "psql",
        "-h", cfg.get("host", "postgres"),
        "-p", str(cfg.get("port", "5432")),
        "-U", cfg.get("user", "postgres"),
        "-v", "ON_ERROR_STOP=1", "-c", sql,
    ])


def psql_seed(cfg: dict, db: str) -> None:
    run_cmd([
        "docker", "run", "-i", "--rm", "--network", PGNET,
        "-e", f"PGPASSWORD={cfg.get('pass', '123')}",
        PGIMAGE, "psql",
        "-h", cfg.get("host", "postgres"),
        "-p", str(cfg.get("port", "5432")),
        "-U", cfg.get("user", "postgres"),
        "-d", db, "-v", "ON_ERROR_STOP=1", "-f", "-",
    ], input_text=SEED)


def db_exists(cfg: dict, name: str) -> bool:
    cmd = [
        "docker", "run", "-i", "--rm", "--network", PGNET,
        "-e", f"PGPASSWORD={cfg.get('pass', '123')}",
        PGIMAGE, "psql",
        "-h", cfg.get("host", "postgres"),
        "-p", str(cfg.get("port", "5432")),
        "-U", cfg.get("user", "postgres"),
        "-tAc", f"SELECT 1 FROM pg_database WHERE datname='{name}'",
    ]
    return subprocess.run(cmd, capture_output=True, text=True).stdout.strip() == "1"


def main() -> None:
    if not DB_FILE.is_file():
        print(f"ERROR: {DB_FILE} 不存在", file=sys.stderr)
        sys.exit(1)
    data = json.loads(DB_FILE.read_text(encoding="utf-8"))
    cfg = data[ENV_NAME]
    for db in cfg.get("dbList", []):
        if not db_exists(cfg, db):
            psql_admin(cfg, f'CREATE DATABASE "{db}";')
            print(f"  已创建库 {db}")
        psql_seed(cfg, db)
    print("==> 环境库初始化完成")


if __name__ == "__main__":
    main()
