# jenkins-config — 流水线定义仓库

类似公司的 `ops/ci2k8s`：**每个目录 = 一个 Jenkins Job 的全部流水线定义**。

## 仓库定位

```
三仓分工：
  jenkins-practice  = 平台层（Jenkins + Registry 怎么部署）
  jenkins-config    = 编排层（每个 Job 的 Jenkinsfile + 脚本）  ← 本仓库
  deepModel         = 业务代码（纯业务，不含 CI 配置）
```

## 目录结构

```
jenkins-config/
├── README.md
└── deepModel/                    # deepModel 项目的 CI/CD
    ├── Jenkinsfile               # 流水线主文件
    └── scripts/
        └── deploy.sh             # 部署脚本（被 deploy Job 调用）
```

## Jenkins Job 配置

Jenkins Job 需要这样配置（UI 或 xml）：

| Job | Definition | SCM | Script Path |
|-----|-----------|-----|-------------|
| `deepModel` | Pipeline from SCM | 本仓库 `main` 分支 | `deepModel/Jenkinsfile` |
| `deepModel-deploy` | Pipeline from SCM | 本仓库 `main` 分支 | `deepModel/Jenkinsfile.deploy` |

## 如何新增一个 Job

1. 创建新目录，如 `myApp/`
2. 在里面写 `Jenkinsfile`（流水线定义）
3. 按需加 `scripts/`（部署脚本等）
4. Jenkins UI 创建 Pipeline Job，指向本仓库对应路径
5. push 到 GitHub

## 和公司 ci2k8s 的对比

| | 公司 ci2k8s | 本仓库 |
|--|------------|--------|
| Job 数量 | ~102 | 目前 1 个 |
| Agent 类型 | K8s Pod | Docker 容器 |
| 部署目标 | TKE + AWS | 本地 Docker |
| 共享脚本 | commonModule/ | 后续按需加 |
