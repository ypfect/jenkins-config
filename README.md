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

## appx（对标 backend-appx-tx 精简版）

```
appx/
├── jobs/appx-ci.xml / appx-deploy.xml
├── Jenkinsfile / Jenkinsfile.deploy
└── scripts/apps-build-steps.sh   # --Module=getAppx|getDbConfig|checkTask|build|...
```

| 公司 | 本地 appx |
|------|-----------|
| `build3.py -a appx` | `--Module=build`（Maven；demo 仓代管业务代码） |
| 参数 Branch / Env / deployID | 同名 |
| appx 端口 8800 | 对外 8800 → 容器 18080（demo jar） |

```bash
cd practice && ./register-jobs.sh appx
./trigger-appx-ci.sh --branch main --env local --deploy-id 10001
./trigger-appx-deploy.sh --image localhost:5050/appx:<N> --env local --deploy-id 10001
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
cd practice && ./register-jobs.sh deepModel appx
```
