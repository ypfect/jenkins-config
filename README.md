# jenkins-config — 流水线定义仓库

对标公司 `ops/ci2k8s`：每个目录 = 一个项目的 Jenkins 流水线配置。

## 三层定位

```
practice/          = 平台层（Jenkins Master + Registry）
config/<project>/  = 编排层（Jenkinsfile + 脚本）      ← 本仓库
<project repo>     = 业务代码
```

## 目录结构

```
config/
├── README.md
└── deepModel/
    ├── jobs/                        # Job 壳子（一次性注册到 Jenkins）
    │   ├── deepModel-ci.xml         #   CI Job：Pipeline from SCM → Jenkinsfile
    │   └── deepModel-deploy.xml     #   CD Job：Pipeline from SCM → Jenkinsfile.deploy
    ├── Jenkinsfile                  # CI 流水线（编译 → 打镜像 → 推仓库 → 触发部署）
    ├── Jenkinsfile.deploy           # CD 流水线（拉镜像 → 部署）
    └── scripts/
        └── deploy.sh               # 部署脚本：pull → 停旧 → 起新 → 健康检查
```

## 工作模式（对标公司 ci2k8s）

**Job 壳子注册一次，流水线在 Git 里持续迭代。**

- `jobs/*.xml` 是 Job 壳子，定义 SCM 地址和 Script Path，**注册一次即可**
- `Jenkinsfile` / `Jenkinsfile.deploy` 是实际流水线逻辑，**git push 即生效**
- `scripts/` 放部署脚本等辅助文件

| 改什么 | 怎么做 |
|--------|--------|
| 流水线逻辑（Stage、步骤） | 改 Jenkinsfile → git push |
| 部署脚本 | 改 scripts/*.sh → git push |
| Job 参数、SCM 路径 | 改 jobs/*.xml → `./register-jobs.sh <project>` |

## 注册 Job

```bash
cd practice

# 注册所有项目
./register-jobs.sh

# 只注册某个项目
./register-jobs.sh deepModel
```

## 如何新增一个项目

```bash
# 1. 创建目录
mkdir -p config/<project>/jobs config/<project>/scripts

# 2. 写 Jenkinsfile
#    参考 deepModel/Jenkinsfile

# 3. 写 Job 壳子 XML
#    参考 deepModel/jobs/deepModel-ci.xml
#    关键：<scriptPath> 指向 <project>/Jenkinsfile

# 4. 注册
cd practice && ./register-jobs.sh <project>
```
