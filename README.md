# Coder 在线开发环境

基于 [Coder](https://coder.com/) 的在线开发环境模板系统，提供 VS Code 在线编辑、文件管理、JupyterLab 等功能。

## 架构概览

```
用户浏览器
    │
    ▼
Coder Server  ──▶  PostgreSQL
    │
    ▼
Docker Engine
    │
    ▼
Workspace 容器（code-server / JupyterLab / FileBrowser）
```

- **Coder Server**：工作空间管理平台，通过 Terraform 模板创建和管理开发容器
- **PostgreSQL**：持久化存储用户、工作空间等元数据
- **Workspace 容器**：基于自定义镜像的开发环境，内置 Python、Node.js 等工具

## 目录结构

```
coder/
├── .github/workflows/     # CI/CD 流水线
├── docker/                 # Docker Compose 编排
│   ├── docker-compose.yml
│   ├── .env.example
│   └── volumes/            # 数据卷（gitignore）
├── images/                 # Docker 镜像定义
│   └── spider/Dockerfile
├── templates/              # Coder 工作空间模板
│   └── spider/
│       ├── main.tf
│       └── scripts/
├── packages/               # 构建产物（gitignore）
├── Makefile                # 构建脚本
└── LICENSE
```

## 快速开始

### 1. 启动 Coder 平台

```bash
cd docker
cp .env.example .env
# 编辑 .env 修改配置（尤其是密码）
docker compose up -d
```

### 2. 打包模板

```bash
make package
```

### 3. 上传模板

在 Coder Web UI 中创建模板，上传 `packages/spider.zip`。

### 4. 创建工作空间

在 Coder Web UI 中基于模板创建工作空间，支持：

- **新建空项目**：创建空目录
- **新建 Scrapy 项目**：自动初始化 Scrapy 项目结构
- **克隆 Git 仓库**：从远程仓库克隆代码

## 可用模板

| 模板 | 说明 | 内置工具 |
|------|------|---------|
| spider | 爬虫开发环境 | Python + uv、Node.js (nvm)、Scrapy、VS Code、JupyterLab、FileBrowser |

## 构建命令

```bash
make help          # 查看所有可用命令
make package       # 打包模板为 zip
make image-build   # 构建 Docker 镜像
make image-push    # 推送镜像到 Registry
make image         # 构建并推送镜像
make clean         # 清理构建产物
make lint          # 代码格式检查
```

## License

[Apache License 2.0](LICENSE)
