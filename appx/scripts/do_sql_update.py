#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
本地简化版 do_sql_update.py（对标 ci2k8s/backend-build-image-tx/scripts/do_sql_update.py）

用法:
  python3 do_sql_update.py <sql_dir> <work_dir> <log_prefix> <db_config.json> <env> <TANANT|IDENTITY>

对环境中 dbList 里的各租户库并行执行 sql_dir 下所有 .sql 文件。
"""
from __future__ import annotations

import json
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path

PGIMAGE = "postgres:16"
PGNET = "practice_default"


def env_cfg(data: dict, env: str) -> dict:
    if env not in data:
        print(f"ERROR: db-config 中无环境 key: {env}", file=sys.stderr)
        sys.exit(1)
    return data[env]


def list_databases(cfg: dict, kind: str) -> list[str]:
    db_list = cfg.get("dbList", [])
    skip = {"camunda", "langflow"}
    if kind == "IDENTITY":
        return [d for d in db_list if d in ("identity", "identity-base")]
    # TANANT: 各业务租户库，不含 tenant-base / identity 等
    skip |= {"tenant-base", "identity", "identity-base"}
    return [d for d in db_list if d not in skip and d.startswith("tenant")]


def psql_base(cfg: dict) -> list[str]:
    return [
        "docker", "run", "-i", "--rm", "--network", PGNET,
        "-e", f"PGPASSWORD={cfg.get('pass', '123')}",
        PGIMAGE, "psql",
        "-h", cfg.get("host", "postgres"),
        "-p", str(cfg.get("port", "5432")),
        "-U", cfg.get("user", "postgres"),
        "-v", "ON_ERROR_STOP=1",
    ]


def run_psql(cfg: dict, db: str, sql: str) -> None:
    cmd = psql_base(cfg) + ["-d", db, "-c", sql]
    print(f"+ psql -d {db} -c {sql[:80]}...")
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        print(p.stdout)
        print(p.stderr, file=sys.stderr)
        raise RuntimeError(f"psql failed on {db}: {p.stderr or p.stdout}")


def run_psql_file(cfg: dict, db: str, path: Path) -> None:
    cmd = psql_base(cfg) + ["-d", db, "-f", "-"]
    print(f"+ psql -d {db} -f {path.name}")
    content = path.read_text(encoding="utf-8")
    p = subprocess.run(cmd, input=content, text=True, capture_output=True)
    if p.returncode != 0:
        print(p.stdout)
        print(p.stderr, file=sys.stderr)
        raise RuntimeError(f"执行 {path.name} 失败 db={db}: {p.stderr or p.stdout}")
    print(f"  数据库:{db} 升级文件:{path.name} 执行成功")


def upgrade_one_db(cfg: dict, db: str, sql_dir: Path, label: str) -> tuple[str, str]:
    started = datetime.now()
    print(f"租户【{db}】数据库升级【{label}】 开始: {started.strftime('%Y-%m-%d %H:%M:%S')}")
    run_psql(cfg, db, "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = current_database() AND pid <> pg_backend_pid();")
    files = sorted(p for p in sql_dir.glob("*.sql") if p.is_file())
    if not files:
        print(f"  WARN: {sql_dir} 下无 .sql，跳过")
        return db, "无 SQL 跳过"
    for f in files:
        run_psql_file(cfg, db, f)
    elapsed = (datetime.now() - started).total_seconds()
    print(f"租户【{db}】执行数据库升级【{label}】结束 耗时:{elapsed:.2f}s")
    return db, "更新完成"


def main() -> None:
    if len(sys.argv) != 7:
        print(
            "用法: do_sql_update.py <sql_dir> <work_dir> <log_prefix> <db_config.json> <env> <TANANT|IDENTITY>",
            file=sys.stderr,
        )
        sys.exit(1)
    sql_dir = Path(sys.argv[1]).resolve()
    db_file = Path(sys.argv[4]).resolve()
    env_name = sys.argv[5]
    kind = sys.argv[6].upper()

    if not sql_dir.is_dir():
        print(f"ERROR: SQL 目录不存在: {sql_dir}", file=sys.stderr)
        sys.exit(1)
    data = json.loads(db_file.read_text(encoding="utf-8"))
    cfg = env_cfg(data, env_name)
    dbs = list_databases(cfg, kind)
    if not dbs:
        print(f"WARN: 无待升级库 kind={kind}")
        return

    print(f"当前升级类型={kind} 环境={env_name} SQL目录={sql_dir}")
    print(f"待更新数据库: {dbs}")

    ok: list[tuple[str, str]] = []
    err: list[str] = []
    with ThreadPoolExecutor(max_workers=min(5, len(dbs))) as pool:
        futures = {
            pool.submit(upgrade_one_db, cfg, db, sql_dir, sql_dir.name): db for db in dbs
        }
        for fut in as_completed(futures):
            db = futures[fut]
            try:
                ok.append(fut.result())
            except Exception as e:
                err.append(f"{db}: {e}")
                print(f"ERROR: {db} 升级失败: {e}", file=sys.stderr)

    print("更新成功的数据库:", ok)
    if err:
        print("更新失败的数据库:", err, file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
