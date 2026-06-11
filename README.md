# jenkins-config — 流水线定义仓库

对标公司 `ops/ci2k8s`：每个目录 = 一个项目的 Jenkins 流水线配置。

## 三层定位

```
practice/          = 平台层（Jenkins Master + Registry）
config/<project>/  = 编排层（Jenkinsfile + 脚本）      ← 本仓库
<project repo>     = 业务代码
```

## deepModel 目录结构

```
deepModel/
├── jobs/
│   ├── deepModel-ci.xml         # CI Job 壳子
│   └── deepModel-deploy.xml     # CD Job 壳子
├── Jenkinsfile                  # CI：checkout → mvn → build → push
├── Jenkinsfile.deploy           # CD：pull → deploy → writeStatus
└── scripts/
    ├── ci-steps.sh              # CI Module 路由（对标 apps-build-steps.py）
    ├── cd-steps.sh              # CD Module 路由
    ├── lib.sh                   # writeStatus mock
    ├── deploy.sh                # 部署脚本
    └── maven/settings.xml       # Maven 阿里云镜像
```

## CI / CD 分工（方案 A）

| Job | 职责 | 参数 |
|-----|------|------|
| `deepModel-ci` | 编译 + 打镜像 + push | BRANCH, Env, deployID |
| `deepModel-deploy` | 拉镜像 + 部署 | IMAGE, Env, deployID, CI_BUILD |

CI **不会**自动触发 CD，需单独触发（Jenkins UI 或 `practice/trigger-deploy.sh`）。

## scripts Module 对照

| 公司 `apps-build-steps.py` | 本地 `ci-steps.sh` / `cd-steps.sh` |
|---------------------------|-----------------------------------|
| `--Module=getAppx` | `logInit` |
| `--Module=build` | `package` |
| docker build/push | `dockerBuild` / `dockerPush` |
| `--Module=writeStatus` | `writeStatus` |
| helm deploy | `cd-steps.sh deploy` |

## appx（对标 backend-appx-tx + **apps/build 为中心**）

与公司一致：**Pod 内以 `apps/build` checkout 到 `apps_src/` 为工作中心**，ci2k8s 只做薄编排。

```
workspace/appx-ci/
├── pipeline/appx/              ← jenkins-config 编排层（Jenkinsfile + apps-build-steps.py）
└── apps_src/                   ← checkout ypfect/77core-apps-build（= 公司 apps/build）
    ├── build3.py / create_db.sh / dbtools.sh / config.yaml
    ├── upgrade/1_before/  upgrade/2_after/
    └── result/                 ← ★ 所有产物（jar / dump / dbtools/*.sql）
```

| 公司 | 本地 |
|------|------|
| ci2k8s `backend-appx-tx/scripts/apps-build-steps.py` | `pipeline/appx/scripts/apps-build-steps.py` |
| checkout `apps/build.git` → `apps_src/` | checkout `77core-apps-build` → `apps_src/` |
| `cd apps_src && python3 build3.py -a appx` | 同命令；Nexus 不可用时 fallback 到 mock-modules |
| `apps-build-pgv14` createdb testapp | compose `postgres` + `--Module=createdb` |
| `genUpgradeScript` → `apps_src/result/dbtools/` | 同路径（本地 mock SQL） |
| Stage10 `do_sql_update.py` ×3 + `create_base_db.py` | 本地简化脚本，对 compose postgres 上 tenant-demo* 三段升级 |
| `apps-build-docker` dockerbuild | `--Module=dockerBuild` 读 `apps_src/result/`（**在打镜像 Stage 位于 DB 升级之后**） |

**Stage 7–10（对标公司 CD 前半段，合并在 CI Job 内练习）：**

| Stage | Module | 说明 |
|-------|--------|------|
| 停服务/备份 | `restartSvc` + `backupdb` | mock 停 appx + pg_dump 租户库 |
| 开始 DB 操作 | `updateWeatherPause` | mock QiQiOps 天气暂停 |
| Tenant 三段升级 | `doSqlUpdate` before → dbtools → after | `Env=local` 时 before/after 用 `scripts/mock/upgrade/` |
| 基准库 | `createBaseDb --DbType=tenant` | 用 `apps_src/result/tenant.dump` 重建 `tenant-base` |

检查阶段会先 `initEnvDbs` 创建 `tenant-demo1/2`、`tenant-public` 等 mock 环境库并灌 `deploy_marker` 种子表。

```bash
cd practice && docker compose up -d postgres && ./register-jobs.sh appx
./trigger-appx-ci.sh --branch master --env local --deploy-id 10001
./trigger-appx-deploy.sh --image localhost:5050/appx:<N> --env local --deploy-id 10001
curl http://localhost:8800/
```

## arap（对标公司"几个 Pod 拉jar→执行数据→对比数据→生产镜像"的完整路径，除 K8s）

arap 在 appx 聚合的基础上，补齐了**数据库环节**：业务源码独立成 GitHub 仓
[`ypfect/arap`](https://github.com/ypfect/arap)（对标公司 `apps/arap`），CI/CD 配置在此。
`docker-compose` 新增 `postgres` 容器（对标构建 Pod 内的 `apps-build-pgv14`）。

```
CI(arap-ci):  拉jar聚合(arap+JDBC)
            → 建临时库 testapp 灌 schema+data+upgrade（执行数据）
            → pg_dump 出 base.dump（基准库）
            → 对比 arap_target 现状，生成增量 upgrade.sql（对比数据）
            → 打镜像(jar+db) → push
CD(arap-deploy): 从镜像取 upgrade.sql 对 arap_target 执行（升级）→ 起服务连库 → curl
```

| 公司路径 | 本地复刻 |
|----------|----------|
| Pod 内 `apps-build-pgv14` | compose `postgres` 容器 |
| `create_db.sh -d testapp` 灌 generated SQL + init-sql | `db-steps.sh createTestDb` 灌 `schema/data/upgrade` |
| `pg_dump -Fc` 出 tenant.dump | `db-steps.sh dumpBase` 出 `base.dump` |
| `dbtools` diff 生成差量升级 SQL | `db-steps.sh genUpgrade` 按 `meta_schema_version.seq` 挑增量 |
| `do_sql_update` 对目标库执行升级 | `deploy.sh` 对 `arap_target` 执行 `upgrade.sql` |
| `dockerbuild.py` 生产镜像 | `dockerBuild`（jar + db 脚本） |

> 真实 arap 依赖内网 Nexus 的 jar、platform 底座与 `dbtools.jar`，本地无法启动；
> 这里用自带 schema 的 mock arap **复刻完整路径形态**，DB 数据是 mock 的。

```bash
cd practice && docker compose up -d postgres && ./register-jobs.sh arap
./trigger-arap-ci.sh --branch main --env local --deploy-id 30001
./trigger-arap-deploy.sh --image localhost:5050/arap:<N> --env local --deploy-id 30001
curl http://localhost:8801/        # 返回库版本 + 应收单列表
# 增量验证：在 arap 仓加 db/upgrade/V<n>__*.sql → 重跑 CI，对比阶段只挑出新增 V<n>
```

## 改什么、怎么做

| 改什么 | 怎么做 |
|--------|--------|
| 流水线 Stage | 改 Jenkinsfile → git push |
| 构建/部署逻辑 | 改 `apps_src/`（77core-apps-build）或 `pipeline/appx/scripts/` → git push |
| Job 参数 | 改 jobs/*.xml → `./register-jobs.sh <project>` |

## 注册 Job

```bash
cd practice && ./register-jobs.sh          # 全部项目
cd practice && ./register-jobs.sh deepModel appx arap
```
