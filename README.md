# jenkins-config — 流水线定义仓库

每个目录 = 一个项目的全部 Jenkins 配置。

## 仓库定位

```
practice/          = 平台层（通用 Jenkins + Registry 环境）
config/<project>/  = 编排层（项目专属 CI/CD 配置）  ← 本仓库
<project repo>     = 业务代码
```

## 目录结构

```
config/
├── README.md
└── deepModel/
    ├── jobs/                        # Job XML（供 init.sh 注册到 Jenkins）
    │   ├── deepModel-ci.xml         #   CI：inline pipeline，git clone → 编译 → 归档
    │   └── deepModel-cd.xml         #   CD：inline pipeline，取 jar → 打镜像 → 部署
    ├── Jenkinsfile                  # CI（SCM Pipeline 模式，更完整的版本）
    ├── Jenkinsfile.deploy           # CD（SCM Pipeline 模式，调用 scripts/deploy.sh）
    └── scripts/
        └── deploy.sh               # 部署脚本：pull → 停旧 → 起新 → 健康检查
```

## 两种 Pipeline 模式

| | Inline（jobs/*.xml） | SCM Pipeline（Jenkinsfile） |
|--|--|--|
| 流水线定义位置 | 嵌在 Job XML 的 `<script>` 里 | 独立 Jenkinsfile 文件 |
| 注册方式 | `init.sh` 复制 XML 到 Jenkins | Jenkins UI 配 SCM 指向本仓库 |
| 修改流水线 | 改 XML → 重新注册或 UI 改 | git push 即生效 |
| 适合场景 | 快速启动、教学演示 | 生产级、多人协作 |

当前 `deepModel-ci.xml` / `deepModel-cd.xml` 用的是 **Inline 模式**（开箱即用）。
`Jenkinsfile` / `Jenkinsfile.deploy` 是同一流水线的 **SCM 版本**（功能更完整，如 Docker Agent 编译、stash/unstash 传递制品）。

## 使用方式

### 方式一：Inline 模式（当前使用）

```bash
# 在 practice/ 下启动 Jenkins 后注册 Job
JOBS_DIR=../config/deepModel/jobs ./init.sh
```

Jenkins UI 直接出现 Job，点 Build Now 即可。

### 方式二：SCM Pipeline 模式

在 Jenkins UI 手动创建 Pipeline Job：
- Definition: Pipeline script from SCM
- SCM: Git → 本仓库 URL
- Script Path: `deepModel/Jenkinsfile`（或 `deepModel/Jenkinsfile.deploy`）

代码推送后 Jenkins 自动拉取最新 Jenkinsfile 执行。

## 如何新增一个项目

1. 创建 `config/<project>/` 目录
2. 至少提供以下之一：
   - `jobs/<job-name>.xml` — Inline 模式，`init.sh` 可直接注册
   - `Jenkinsfile` — SCM 模式，Jenkins UI 配 SCM 路径
3. 按需加 `scripts/`（部署脚本等）
4. 注册：`JOBS_DIR=../config/<project>/jobs ./init.sh`
