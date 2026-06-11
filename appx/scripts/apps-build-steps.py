#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
appx CI/CD Module 路由（对标公司 ci2k8s/backend-appx-tx/scripts/apps-build-steps.py）

编排层只负责 --Module=xxx 分发；构建/DB/产物均在 checkout 后的 apps_src/（= apps/build）内完成。
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

WORKSPACE = Path(os.environ.get("WORKSPACE", ".")).resolve()
PIPELINE_APPX = WORKSPACE / "pipeline" / "appx"
APPS_SRC = WORKSPACE / "apps_src"
SCRIPTS = PIPELINE_APPX / "scripts"
MOCK_DB = SCRIPTS / "mock" / "db-config.local.json"
STATUS_DIR = Path("/var/jenkins_home/deploy-status")


def env(k: str, default: str = "") -> str:
    return os.environ.get(k, default)


def run(cmd: str | list[str], *, cwd: Path | None = None, check: bool = True) -> int:
    if isinstance(cmd, str):
        print(f"+ {cmd}")
        p = subprocess.run(cmd, shell=True, cwd=cwd, executable="/bin/bash")
    else:
        print(f"+ {' '.join(cmd)}")
        p = subprocess.run(cmd, cwd=cwd)
    if check and p.returncode != 0:
        sys.exit(p.returncode)
    return p.returncode


def db_config_file() -> Path:
    f = env("DBFILES")
    if f:
        return WORKSPACE / f
    return WORKSPACE / "postgres.local-db-config.json"


def build_db_name() -> str:
    meta = WORKSPACE / ".build_meta.json"
    if meta.is_file():
        try:
            return json.loads(meta.read_text(encoding="utf-8"))["BUILD_DB_NAME"]
        except (KeyError, json.JSONDecodeError):
            pass
    name = env("DBName")
    if name:
        return name
    ts = datetime.now().strftime("%Y%m%d%H%M%S")
    branch = env("Branch", "main").replace("/", "_")
    return f"apps-build_{env('Env', 'local')}_{branch}_{env('BUILD_NUMBER', '0')}_{ts}"


def write_status(status: str) -> None:
    deploy_id = env("deployID") or "none"
    STATUS_DIR.mkdir(parents=True, exist_ok=True)
    body = {
        "deployID": deploy_id,
        "env": env("Env", "local"),
        "service": env("BUILD_SERVICE", "appx"),
        "job": env("JOB_TYPE", "ci"),
        "status": status,
        "buildNumber": env("BUILD_NUMBER", ""),
        "branch": env("Branch", ""),
        "image": env("IMAGE", ""),
        "timestamp": datetime.now().astimezone().isoformat(timespec="seconds"),
    }
    path = STATUS_DIR / f"{deploy_id}.json"
    path.write_text(json.dumps(body, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"==> 状态已记录: {path}")
    print(path.read_text(encoding="utf-8"))


def psql_network_args() -> list[str]:
    net = env("PG_NETWORK", "practice_default")
    host = env("PG_HOST", "postgres")
    return [
        "docker", "run", "-i", "--rm", "--network", net,
        "-e", f"PGPASSWORD={env('PGPASS', '123')}",
        "postgres:16", "psql",
        "-h", host, "-p", "5432", "-U", env("PGUSER", "postgres"),
        "-v", "ON_ERROR_STOP=1",
    ]


def module_get_appx(_: argparse.Namespace) -> None:
    svc = env("BUILD_SERVICE", "appx")
    print(f"BUILD_SERVICE={svc}")
    print(f"build apps = ['{svc}']")


def module_get_db_config(_: argparse.Namespace) -> None:
    if not MOCK_DB.is_file():
        print(f"ERROR: 未找到 mock db 配置 {MOCK_DB}", file=sys.stderr)
        sys.exit(1)
    target = db_config_file()
    shutil.copy2(MOCK_DB, target)
    print(f"==> 已写入 {target.name}（mock getDbConfig）")
    print(target.read_text(encoding="utf-8"))


def module_check_task(_: argparse.Namespace) -> None:
    print(f"==> checkTask OK（本地练习跳过互斥锁） Env={env('Env', 'local')} Branch={env('Branch', 'main')}")


def module_insert_dbinfo(_: argparse.Namespace) -> None:
    target = db_config_file()
    if not target.is_file():
        print(f"ERROR: DB 配置文件不存在: {target}", file=sys.stderr)
        sys.exit(1)
    data = json.loads(target.read_text(encoding="utf-8"))
    db_name = build_db_name()
    data[db_name] = {
        "host": env("DBHost", "postgres"),
        "port": env("DBPort", "5432"),
        "user": env("DBUser", "postgres"),
        "pass": env("DBPswd", "123"),
    }
    target.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (WORKSPACE / ".build_meta.json").write_text(
        json.dumps({"BUILD_DB_NAME": db_name}, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    os.environ["BUILD_DB_NAME"] = db_name
    print(f"向数据库文件 {target.name} 中插入数据库信息 {data[db_name]} 成功")
    print(f"BUILD_DB_NAME={db_name}")


def module_callback_log(_: argparse.Namespace) -> None:
    print(f"[callbackLog] deployID={env('deployID')} Env={env('Env', 'local')} {env('LOG_INFO', '')}")


def module_createdb(_: argparse.Namespace) -> None:
    print("==> [apps-build-pgv14] createdb testapp")
    cmd = psql_network_args() + ["-c", "DROP DATABASE IF EXISTS testapp;", "-c", "CREATE DATABASE testapp;"]
    run(cmd)


def module_prepare_build(_: argparse.Namespace) -> None:
    if not APPS_SRC.is_dir():
        print(f"ERROR: apps_src 不存在，请先 checkout 77core-apps-build", file=sys.stderr)
        sys.exit(1)
    dockerfile = PIPELINE_APPX / "Dockerfile"
    if dockerfile.is_file():
        shutil.copy2(dockerfile, APPS_SRC / "Dockerfile")
        print(f"==> 已复制 Dockerfile → apps_src/")
    settings = PIPELINE_APPX / "maven" / "settings.xml"
    if settings.is_file():
        dest = Path("/usr/local/apache-maven-3.6.1/conf/settings.xml")
        if dest.parent.is_dir():
            shutil.copy2(settings, dest)
        os.environ["MAVEN_SETTINGS"] = str(settings)
    print("==> apps_src 目录:")
    run(f"ls -al {APPS_SRC}")


def module_build(_: argparse.Namespace) -> None:
    if not APPS_SRC.is_dir():
        print("ERROR: apps_src 不存在", file=sys.stderr)
        sys.exit(1)
    settings = PIPELINE_APPX / "maven" / "settings.xml"
    m2 = env("MAVEN_REPO", "/root/.m2/repository")
    env_prefix = f"MAVEN_OPTS='-Dmaven.repo.local={m2}' "
    if settings.is_file():
        env_prefix += f"MAVEN_ARGS='-s {settings} -Dmaven.repo.local={m2}' "
    print("==> cd apps_src && python3 -u build3.py -a appx")
    rc = subprocess.run(
        f"{env_prefix}python3 -u build3.py -a appx",
        shell=True,
        cwd=APPS_SRC,
        executable="/bin/bash",
    ).returncode
    if rc == 0:
        print("==> build3.py 完成")
        return
    if env("Env", "local") != "local":
        sys.exit(rc)
    print("WARN: build3.py 失败（通常因 Nexus 无 com.q7link.* jar），启用本地 fallback")
    fallback = SCRIPTS / "local-build-fallback.sh"
    run(["bash", str(fallback)])


def module_gen_upgrade_script(args: argparse.Namespace) -> None:
    dbtools_dir = APPS_SRC / "result" / "dbtools"
    dbtools_dir.mkdir(parents=True, exist_ok=True)
    build_db = env("BUILD_DB_NAME") or build_db_name()
    env_name = env("Env", "local")
    out_sql = dbtools_dir / f"{build_db}_to_{env_name}.tenantallin-base.sql"
    print(f"==> [genUpgradeScript] DbtoolsPath={dbtools_dir} BUILD_DB_NAME={build_db}")
    if (APPS_SRC / "dbtools.sh").is_file() and env("USE_REAL_DBTOOLS") == "1":
        run(["bash", "dbtools.sh"], cwd=APPS_SRC, check=False)
    if not out_sql.is_file() or out_sql.stat().st_size == 0:
        local = SCRIPTS / "local-gen-upgrade.sh"
        if local.is_file():
            os.environ.setdefault("BUILD_DB_NAME", build_db)
            run(["bash", str(local)])
        else:
            out_sql.write_text(
                f"-- local mock genUpgradeScript\n-- source: {build_db}.tenant\n"
                f"-- target: {env_name}.tenant-base\nSELECT 1;\n",
                encoding="utf-8",
            )
    print(f"==> 升级 SQL: {out_sql}")
    if out_sql.is_file():
        print(out_sql.read_text(encoding="utf-8")[:2000])


def module_check_db_buildtime(_: argparse.Namespace) -> None:
    print("==> check_db_buildtime OK（本地练习跳过）")


def module_docker_build(_: argparse.Namespace) -> None:
    reg = env("REGISTRY", "localhost:5050")
    name = env("IMAGE_NAME", "appx")
    num = env("BUILD_NUMBER", "latest")
    result = APPS_SRC / "result"
    if not (result / "app.jar").is_file() and list(result.glob("appx-*.jar")):
        jars = sorted(result.glob("appx-*.jar"))
        shutil.copy2(jars[-1], result / "app.jar")
    if not (result / "Dockerfile").is_file() and (APPS_SRC / "Dockerfile").is_file():
        shutil.copy2(APPS_SRC / "Dockerfile", result / "Dockerfile")
    run(
        f"docker build -t {reg}/{name}:{num} -t {reg}/{name}:latest {result}",
        check=True,
    )


def module_docker_push(_: argparse.Namespace) -> None:
    reg = env("REGISTRY", "localhost:5050")
    name = env("IMAGE_NAME", "appx")
    num = env("BUILD_NUMBER", "latest")
    run(f"docker push {reg}/{name}:{num}")
    run(f"docker push {reg}/{name}:latest")
    os.environ["IMAGE"] = f"{reg}/{name}:{num}"
    print(f"==> 镜像已推送: {reg}/{name}:{num}")


def module_deploy(_: argparse.Namespace) -> None:
    if not env("IMAGE"):
        print("ERROR: IMAGE 不能为空", file=sys.stderr)
        sys.exit(1)
    deploy_sh = SCRIPTS / "deploy.sh"
    run(["bash", str(deploy_sh)])


def module_write_status(args: argparse.Namespace) -> None:
    write_status(env("STATUS", args.taskStatus or "SUCCESS"))


MODULES = {
    "getAppx": module_get_appx,
    "getDbConfig": module_get_db_config,
    "checkTask": module_check_task,
    "insertDbinfo": module_insert_dbinfo,
    "callbackLog": module_callback_log,
    "createdb": module_createdb,
    "prepareBuild": module_prepare_build,
    "build": module_build,
    "genUpgradeScript": module_gen_upgrade_script,
    "checkDbBuildtime": module_check_db_buildtime,
    "dockerBuild": module_docker_build,
    "dockerPush": module_docker_push,
    "deploy": module_deploy,
    "writeStatus": module_write_status,
}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--Module", required=True)
    parser.add_argument("--Env")
    parser.add_argument("--Branch")
    parser.add_argument("--deployID")
    parser.add_argument("--taskStatus")
    parser.add_argument("--buildID")
    parser.add_argument("--log_info")
    parser.add_argument("--DBfiles")
    parser.add_argument("--DBName")
    parser.add_argument("--DBHost")
    parser.add_argument("--DBPort")
    parser.add_argument("--DBUser")
    parser.add_argument("--DBPswd")
    parser.add_argument("--DbtoolsPath")
    parser.add_argument("--BUILD_DB_NAME")
    parser.add_argument("--CI_BUILD")
    args = parser.parse_args()
    for k, v in vars(args).items():
        if v is not None and k != "Module":
            os.environ[k if k != "log_info" else "LOG_INFO"] = str(v)
    if args.buildID:
        os.environ["BUILD_NUMBER"] = args.buildID
    if args.taskStatus:
        os.environ["STATUS"] = args.taskStatus
    fn = MODULES.get(args.Module)
    if not fn:
        print(f"未知 Module: {args.Module}", file=sys.stderr)
        print("可用:", ", ".join(MODULES), file=sys.stderr)
        sys.exit(1)
    fn(args)


if __name__ == "__main__":
    main()
