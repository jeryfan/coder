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
  username = data.coder_workspace_owner.me.name
}

variable "docker_socket" {
  default     = ""
  description = "(Optional) Docker socket URI"
  type        = string
}

provider "docker" {
  host = var.docker_socket != "" ? var.docker_socket : null
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "coder_parameter" "project_name" {
  name         = "project_name"
  display_name = "爬虫项目名称"
  type         = "string"
  default      = "my_spider"
  mutable      = false
  validation {
    regex = "^[a-zA-Z][a-zA-Z0-9_]*$"
    error = "项目名必须以字母开头，只能包含字母、数字、下划线"
  }
}

resource "coder_agent" "main" {
  arch           = data.coder_provisioner.me.arch
  os             = "linux"
  startup_script = <<-EOT
    set -e

    # Prepare user home with default files on first start.
    if [ ! -f ~/.init_done ]; then
      cp -rT /etc/skel ~
      touch ~/.init_done
    fi

    PROJECT_NAME="${data.coder_parameter.project_name.value}"
    PROJECT_DIR="/home/coder/$PROJECT_NAME"

    echo "========================================"
    echo "  Scrapy 爬虫开发环境初始化"
    echo "  开始时间: $(date)"
    echo "========================================"

    # 安装系统依赖
    echo "[1/3] 安装系统依赖..."
    sudo apt-get update -qq 2>/dev/null || true
    sudo apt-get install -y -qq python3-pip python3-venv git vim curl wget 2>/dev/null || true

    # 创建 Python 虚拟环境
    echo "[2/3] 设置 Python 虚拟环境..."
    mkdir -p /home/coder/.venvs
    if [ ! -d /home/coder/.venvs/scrapy-env ]; then
        python3 -m venv /home/coder/.venvs/scrapy-env
    fi
    source /home/coder/.venvs/scrapy-env/bin/activate
    pip install -q --upgrade pip
    pip install -q --no-cache-dir scrapy requests beautifulsoup4 lxml pandas openpyxl pymongo redis fake-useragent jupyter jupyterlab ipython black isort 2>&1 | tail -3
    echo "  Python依赖安装完成"

    # 创建 Scrapy 项目
    echo "[3/3] 创建 Scrapy 项目..."
    cd /home/coder
    if [ ! -d "$PROJECT_DIR" ]; then
        scrapy startproject "$PROJECT_NAME"
    fi

    # 设置权限
    sudo chown -R coder:coder /home/coder/.venvs 2>/dev/null || true
    sudo chown -R coder:coder "$PROJECT_DIR" 2>/dev/null || true

    # 配置环境变量
    if ! grep -q "scrapy-env" /home/coder/.bashrc 2>/dev/null; then
        echo 'source /home/coder/.venvs/scrapy-env/bin/activate' >> /home/coder/.bashrc
    fi

    echo ""
    echo "========================================"
    echo "  爬虫开发环境已就绪!"
    echo "  完成时间: $(date)"
    echo "========================================"
  EOT

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

# 使用官方 code-server 模块
module "code-server" {
  count  = data.coder_workspace.me.start_count
  source = "registry.coder.com/coder/code-server/coder"
  version = "~> 1.0"

  agent_id = coder_agent.main.id
  folder   = "/home/coder/${data.coder_parameter.project_name.value}"
  order    = 1
}

# 使用官方 JupyterLab 模块
module "jupyterlab" {
  count  = data.coder_workspace.me.start_count
  source = "registry.coder.com/coder/jupyterlab/coder"
  version = "~> 1.0"

  agent_id  = coder_agent.main.id
  order     = 2
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
  image    = "codercom/enterprise-base:ubuntu"
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

output "project_directory" {
  value = "/home/coder/${data.coder_parameter.project_name.value}"
}
