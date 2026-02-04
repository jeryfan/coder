terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

locals {
  project_name = data.coder_parameter.name.value
  project_dir  = "/home/coder/${local.project_name}"
  source       = data.coder_parameter.source.value
  repo         = data.coder_parameter.repo.value
  node_version = data.coder_parameter.node_version.value
}

variable "docker_socket" {
  default     = ""
  description = "(Optional) Docker socket URI"
  type        = string
}

variable "docker_image" {
  default     = "codercom/enterprise-base:ubuntu"
  description = "Base image for the workspace container"
  type        = string
}

provider "docker" {
  host = var.docker_socket != "" ? var.docker_socket : null
}

provider "coder" {}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# 项目来源
data "coder_parameter" "source" {
  name         = "source"
  display_name = "项目来源"
  type         = "string"
  default      = "empty"
  mutable      = false
  option {
    name  = "新建空项目"
    value = "empty"
  }
  option {
    name  = "新建 Scrapy 项目"
    value = "scrapy"
  }
  option {
    name  = "克隆 Git 仓库"
    value = "git"
  }
  option {
    name  = "上传文件"
    value = "upload"
  }
}

# 项目名称
data "coder_parameter" "name" {
  name         = "name"
  display_name = "项目名称"
  type         = "string"
  default      = "my_project"
  mutable      = false
  validation {
    regex = "^[a-zA-Z][a-zA-Z0-9_-]*$"
    error = "项目名必须以字母开头，只能包含字母、数字、下划线、连字符"
  }
}

# Git 仓库地址
data "coder_parameter" "repo" {
  name         = "repo"
  display_name = "Git 仓库地址"
  type         = "string"
  default      = ""
  mutable      = false
  validation {
    regex = "^$|^(https?|ssh|git)://|^git@"
    error = "请输入有效的 Git 仓库地址（https://、ssh://、git:// 或 git@ 开头），或保持为空"
  }
}

# Node 版本
data "coder_parameter" "node_version" {
  name         = "node_version"
  display_name = "Node 版本 (nvm)"
  type         = "string"
  default      = "lts/*"
  mutable      = true
  description  = "示例: lts/*、20、18"
}

# 启用的工具
data "coder_parameter" "enable_code_server" {
  name         = "enable_code_server"
  display_name = "启用 VS Code (code-server)"
  type         = "bool"
  default      = true
  mutable      = true
}

data "coder_parameter" "enable_jupyterlab" {
  name         = "enable_jupyterlab"
  display_name = "启用 JupyterLab"
  type         = "bool"
  default      = true
  mutable      = true
}

data "coder_parameter" "enable_filebrowser" {
  name         = "enable_filebrowser"
  display_name = "启用文件管理器"
  type         = "bool"
  default      = true
  mutable      = true
}

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"

  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = "${data.coder_workspace_owner.me.email}"
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = "${data.coder_workspace_owner.me.email}"
  }

  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Home Disk"
    key          = "3_home_disk"
    script       = "coder stat disk --path $HOME"
    interval     = 60
    timeout      = 1
  }
}

resource "coder_script" "workspace_init" {
  agent_id            = coder_agent.main.id
  display_name        = "Workspace Init"
  icon                = "/icon/package.svg"
  run_on_start        = true
  start_blocks_login  = true
  timeout             = 1800

  script = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail

    if [ ! -f "$HOME/.init_done" ]; then
      cp -rT /etc/skel "$HOME"
      touch "$HOME/.init_done"
    fi

    SOURCE="${local.source}"
    NAME="${local.project_name}"
    REPO="${local.repo}"
    PROJECT_DIR="${local.project_dir}"
    NODE_VERSION="${local.node_version}"

    echo "========================================"
    echo "  爬虫开发环境初始化"
    echo "  项目来源: $SOURCE"
    echo "  项目名称: $NAME"
    echo "  Node 版本: $NODE_VERSION"
    echo "  开始时间: $(date)"
    echo "========================================"

    if [ "$SOURCE" = "git" ] && [ -z "$REPO" ]; then
      echo "错误: 选择了 Git 仓库来源但未提供仓库地址"
      exit 1
    fi

    # 安装系统依赖
    echo "[1/5] 安装系统依赖..."
    export DEBIAN_FRONTEND=noninteractive
    if [ ! -f "$HOME/.apt_done" ]; then
      if sudo apt-get update -qq 2>/dev/null; then
        sudo apt-get install -y -qq python3-pip python3-venv git vim curl wget unzip 2>/dev/null
        touch "$HOME/.apt_done"
      else
        echo "警告: apt-get update 失败，已跳过系统依赖安装"
      fi
    fi

    if ! command -v curl >/dev/null 2>&1; then
      echo "警告: curl 未安装，跳过 nvm/Node/uv 安装"
    else
      # 安装 nvm
      echo "[2/5] 安装 nvm..."
      export NVM_DIR="$HOME/.nvm"
      if [ ! -s "$NVM_DIR/nvm.sh" ]; then
        export PROFILE="$HOME/.bashrc"
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
      fi
      if ! grep -q 'NVM_DIR' "$HOME/.bashrc" 2>/dev/null; then
        cat >> "$HOME/.bashrc" <<'EOF'
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
EOF
      fi
      if [ -s "$NVM_DIR/nvm.sh" ]; then
        . "$NVM_DIR/nvm.sh"
      fi

      # 安装 Node (LTS)
      echo "[3/5] 安装 Node (nvm)..."
      if command -v nvm >/dev/null 2>&1; then
        nvm install "$NODE_VERSION"
        nvm alias default "$NODE_VERSION"
      else
        echo "警告: nvm 未就绪，跳过 Node 安装"
      fi

      # 安装 uv
      echo "[4/5] 安装 uv..."
      mkdir -p "$HOME/.local/bin"
      if [ ! -x "$HOME/.local/bin/uv" ]; then
        curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR="$HOME/.local/bin" UV_NO_MODIFY_PATH=1 sh
      fi
      export PATH="$HOME/.local/bin:$PATH"
      if ! grep -q '/.local/bin' "$HOME/.bashrc" 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
      fi
    fi

    # 初始化项目
    echo "[5/5] 初始化项目..."
    cd "$HOME"
    if [ ! -d "$PROJECT_DIR" ]; then
        case "$SOURCE" in
            empty)
                mkdir -p "$PROJECT_DIR"
                ;;
            scrapy)
                if command -v uv >/dev/null 2>&1; then
                  cd "$HOME"
                  uv init "$NAME"
                  cd "$PROJECT_DIR"
                  uv add scrapy
                  if [ ! -f "$PROJECT_DIR/scrapy.cfg" ]; then
                    uv run scrapy startproject "$NAME" .
                  fi
                else
                  mkdir -p "$PROJECT_DIR"
                  cat > "$PROJECT_DIR/README.md" <<'EOF'
本项目选择了 Scrapy 模板，但当前环境未安装 uv。
请先安装 uv 后执行:
  cd "$HOME"
  uv init <项目名>
  cd <项目名>
  uv add scrapy
  uv run scrapy startproject <项目名> .
EOF
                fi
                ;;
            git)
                git clone "$REPO" "$PROJECT_DIR"
                ;;
            upload)
                mkdir -p "$PROJECT_DIR"
                ;;
        esac
    fi

    # 设置权限
    sudo chown -R coder:coder "$PROJECT_DIR" 2>/dev/null || true

    echo ""
    echo "========================================"
    echo "  开发环境已就绪!"
    echo "  项目目录: $PROJECT_DIR"
    echo "  完成时间: $(date)"
    echo "========================================"
  EOT
}

# VS Code 编辑器
module "code-server" {
  count   = data.coder_parameter.enable_code_server.value ? data.coder_workspace.me.start_count : 0
  source  = "registry.coder.com/coder/code-server/coder"
  version = "~> 1.0"

  agent_id = coder_agent.main.id
  folder   = "/home/coder"
  order    = 1
}

# JupyterLab
module "jupyterlab" {
  count   = data.coder_parameter.enable_jupyterlab.value ? data.coder_workspace.me.start_count : 0
  source  = "registry.coder.com/coder/jupyterlab/coder"
  version = "~> 1.0"

  agent_id  = coder_agent.main.id
  order     = 2
  subdomain = false
}

# 文件管理器
module "filebrowser" {
  count   = data.coder_parameter.enable_filebrowser.value ? data.coder_workspace.me.start_count : 0
  source  = "registry.coder.com/coder/filebrowser/coder"
  version = "~> 1.0"

  agent_id  = coder_agent.main.id
  order     = 3
  subdomain = false
}

resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"
  lifecycle {
    ignore_changes = all
  }
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

resource "docker_container" "workspace" {
  count    = data.coder_workspace.me.start_count
  image    = var.docker_image
  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name
  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env        = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }
}

resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = docker_container.workspace[0].id
  item {
    key   = "project_dir"
    value = local.project_dir
  }
  item {
    key   = "source"
    value = local.source
  }
  item {
    key   = "repo"
    value = local.repo != "" ? local.repo : "N/A"
  }
  item {
    key   = "image"
    value = var.docker_image
  }
}

output "project_directory" {
  value = local.project_dir
}
