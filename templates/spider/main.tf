# Spider 工作空间模板
#
# 提供基于 Docker 的爬虫开发环境，内置 code-server (VS Code)、
# JupyterLab、FileBrowser，支持新建空项目、Scrapy 项目或克隆 Git 仓库。

terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.17"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = ">= 3.0"
    }
  }
}

# ── Variables ────────────────────────────────────────────

variable "docker_socket" {
  default     = ""
  description = "(Optional) Docker socket URI"
  type        = string
}

variable "docker_image" {
  default     = "ghcr.io/jeryfan/coder-spider:latest"
  description = "Base image for the workspace container"
  type        = string
}

variable "memory" {
  default     = 2048
  description = "Memory limit for the workspace container (MB)"
  type        = number
}

variable "cpu_shares" {
  default     = 1024
  description = "CPU shares for the workspace container"
  type        = number
}

variable "coder_network_name" {
  default     = "coder-network"
  description = "Docker network name used by the Coder server container"
  type        = string
}

# ── Providers ────────────────────────────────────────────

provider "docker" {
  host = var.docker_socket != "" ? var.docker_socket : null
}

provider "coder" {}

# ── Data Sources ─────────────────────────────────────────

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# ── Parameters ───────────────────────────────────────────

data "coder_parameter" "source" {
  name         = "source"
  display_name = "项目来源"
  description  = "选择项目的初始化方式：新建空项目、Scrapy 模板或从 Git 仓库克隆"
  type         = "string"
  default      = "empty"
  mutable      = false
  order        = 1
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
}

data "coder_parameter" "name" {
  name         = "name"
  display_name = "项目名称"
  description  = "项目目录名，将创建在 ~/workspace/ 下"
  type         = "string"
  default      = "my_project"
  mutable      = false
  order        = 2
  validation {
    regex = "^[a-zA-Z][a-zA-Z0-9_-]*$"
    error = "项目名必须以字母开头，只能包含字母、数字、下划线、连字符"
  }
}

data "coder_parameter" "repo" {
  name         = "repo"
  display_name = "Git 仓库地址"
  description  = "当项目来源选择「克隆 Git 仓库」时填写，支持 HTTPS 和 SSH 地址"
  type         = "string"
  default      = ""
  mutable      = false
  order        = 3
  validation {
    regex = "^$|^(https?|ssh|git)://|^git@"
    error = "请输入有效的 Git 仓库地址（https://、ssh://、git:// 或 git@ 开头），或保持为空"
  }
}

# ── Locals ───────────────────────────────────────────────

locals {
  project_name  = data.coder_parameter.name.value
  workspace_dir = "/home/coder/workspace"
  project_dir   = "${local.workspace_dir}/${local.project_name}"
  source        = data.coder_parameter.source.value
  repo          = data.coder_parameter.repo.value
}

# ── Agent ────────────────────────────────────────────────

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
  agent_id           = coder_agent.main.id
  display_name       = "Workspace Init"
  icon               = "/icon/package.svg"
  run_on_start       = true
  start_blocks_login = true
  timeout            = 1800

  script = templatefile("${path.module}/scripts/workspace-init.sh", {
    source        = local.source
    name          = local.project_name
    repo          = local.repo
    workspace_dir = local.workspace_dir
    project_dir   = local.project_dir
  })
}

# ── Apps ─────────────────────────────────────────────────

module "code-server" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/code-server/coder"
  version = "~> 1.0"

  agent_id = coder_agent.main.id
  folder   = local.workspace_dir
  extensions = [
    "ms-python.python",
  ]
  order = 1
}

module "jupyterlab" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/jupyterlab/coder"
  version = "~> 1.0"

  agent_id  = coder_agent.main.id
  order     = 2
  subdomain = false
}

module "filebrowser" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/filebrowser/coder"
  version = "~> 1.0"

  agent_id  = coder_agent.main.id
  order     = 3
  subdomain = false
}

# ── Infrastructure ───────────────────────────────────────

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
  count      = data.coder_workspace.me.start_count
  image      = var.docker_image
  name       = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname   = data.coder_workspace.me.name
  memory     = var.memory
  cpu_shares = var.cpu_shares
  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "coder-server")]
  env        = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  networks_advanced {
    name = var.coder_network_name
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

# ── Outputs ──────────────────────────────────────────────

output "project_directory" {
  value = local.project_dir
}
