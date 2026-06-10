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

## appx（对标 backend-appx-tx + apps/build/build3.py）

appx 的本质是**聚合 jar**：按 `config.yaml` 版本清单，从 Maven 仓库拉各模块已发布的
二进制 jar → 解包 → 合并到主壳 → `jar` 重打包成一个 mono fat jar。**全程不编译业务源码**。

```
appx/
├── config.yaml                   # 版本清单（mono.appx + modules）= 公司 apps/build/config.yaml
├── mock-modules/                 # 模拟"已发布到 Nexus 的模块"：appx 主壳 + mod-a + mod-b
├── Dockerfile                    # 业务镜像模板
├── jobs/appx-ci.xml / appx-deploy.xml
├── Jenkinsfile / Jenkinsfile.deploy
└── scripts/
    ├── apps-build-steps.sh       # --Module=getAppx|checkTask|build|dockerBuild|...
    └── build.sh                  # 核心聚合：install→unpack→cp 合并→jar 重打包（对标 build3.py）
```

| 公司 apps/build/build3.py | 本地 build.sh |
|--------------------------|---------------|
| `config.yaml` 版本清单 | 同名同结构 |
| `mvn dependency:unpack` 从 Nexus 拉各 app jar | 同命令，从本地 m2 拉 mock 模块 jar |
| `cp -Rf BOOT-INF/classes/* lib/*` 合并到主 appx | `cp -Rf` 合并到主壳 |
| 合并 string-res / aware / kmodule.xml | 合并 `appx-modules.list` 清单碎片 |
| `jar cfM0 result/appx-<ver>.jar *` | `jar cfe result/appx-<ver>.jar` |

> 首段 `mvn install` 仅用于在本地 m2 "模拟模块已发布到 Nexus"，对标公司各 app 工程已各自 CI 发布。

```bash
cd practice && ./register-jobs.sh appx
./trigger-appx-ci.sh --branch main --env local --deploy-id 10001
./trigger-appx-deploy.sh --image localhost:5050/appx:<N> --env local --deploy-id 10001
# 部署后验证：curl http://localhost:8800/  → 返回聚合的模块列表
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
| 构建/部署逻辑 | 改 scripts/*.sh → git push |
| Job 参数 | 改 jobs/*.xml → `./register-jobs.sh <project>` |

## 注册 Job

```bash
cd practice && ./register-jobs.sh          # 全部项目
cd practice && ./register-jobs.sh deepModel appx arap
```
