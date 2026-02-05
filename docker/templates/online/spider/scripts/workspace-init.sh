#!/usr/bin/env bash
set -euo pipefail

log()  { printf '%s\n' "$*"; }
warn() { printf '警告: %s\n' "$*" >&2; }
die()  { printf '错误: %s\n' "$*" >&2; exit 1; }

SOURCE="${source}"
NAME="${name}"
REPO="${repo}"
PROJECT_DIR="${project_dir}"
NODE_VERSION="${node_version}"

init_home() {
  if [ ! -f "$HOME/.init_done" ]; then
    cp -rT /etc/skel "$HOME"
    touch "$HOME/.init_done"
  fi
}

append_nvm_bashrc() {
  if ! grep -q 'NVM_DIR' "$HOME/.bashrc" 2>/dev/null; then
    {
      echo 'export NVM_DIR="$HOME/.nvm"'
      echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"'
      echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"'
    } >> "$HOME/.bashrc"
  fi
}

install_apt() {
  log "[1/5] 安装系统依赖..."
  export DEBIAN_FRONTEND=noninteractive
  if [ ! -f "$HOME/.apt_done" ]; then
    if sudo apt-get update -qq 2>/dev/null; then
      sudo apt-get install -y -qq python3-pip python3-venv git vim curl wget unzip 2>/dev/null
      touch "$HOME/.apt_done"
    else
      warn "apt-get update 失败，已跳过系统依赖安装"
    fi
  fi
}

install_nvm_and_node() {
  log "[2/5] 安装 nvm..."
  export NVM_DIR="$HOME/.nvm"
  if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    export PROFILE="$HOME/.bashrc"
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
  fi
  append_nvm_bashrc
  if [ -s "$NVM_DIR/nvm.sh" ]; then
    . "$NVM_DIR/nvm.sh"
  fi

  log "[3/5] 安装 Node (nvm)..."
  if command -v nvm >/dev/null 2>&1; then
    nvm install "$NODE_VERSION"
    nvm alias default "$NODE_VERSION"
  else
    warn "nvm 未就绪，跳过 Node 安装"
  fi
}

install_uv() {
  log "[4/5] 安装 uv..."
  mkdir -p "$HOME/.local/bin"
  if [ ! -x "$HOME/.local/bin/uv" ]; then
    curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR="$HOME/.local/bin" UV_NO_MODIFY_PATH=1 sh
  fi
  export PATH="$HOME/.local/bin:$PATH"
  if ! grep -q '/.local/bin' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
  fi
}

write_scrapy_readme() {
  printf '%s\n' \
    '本项目选择了 Scrapy 模板，但当前环境未安装 uv。' \
    '请先安装 uv 后执行:' \
    '  cd "$HOME"' \
    '  uv init <项目名>' \
    '  cd <项目名>' \
    '  uv add scrapy' \
    '  uv run scrapy startproject <项目名> .' \
    > "$PROJECT_DIR/README.md"
}

init_project() {
  log "[5/5] 初始化项目..."
  cd "$HOME"
  if [ -d "$PROJECT_DIR" ]; then
    return
  fi

  case "$SOURCE" in
    empty)
      mkdir -p "$PROJECT_DIR"
      ;;
    scrapy)
      if command -v uv >/dev/null 2>&1; then
        uv init "$NAME"
        cd "$PROJECT_DIR"
        uv add scrapy
        if [ ! -f "$PROJECT_DIR/scrapy.cfg" ]; then
          uv run scrapy startproject "$NAME" .
        fi
      else
        mkdir -p "$PROJECT_DIR"
        write_scrapy_readme
      fi
      ;;
    git)
      git clone "$REPO" "$PROJECT_DIR"
      ;;
    upload)
      mkdir -p "$PROJECT_DIR"
      ;;
  esac
}

log "========================================"
log "  爬虫开发环境初始化"
log "  项目来源: $SOURCE"
log "  项目名称: $NAME"
log "  Node 版本: $NODE_VERSION"
log "  开始时间: $(date)"
log "========================================"

if [ "$SOURCE" = "git" ] && [ -z "$REPO" ]; then
  die "选择了 Git 仓库来源但未提供仓库地址"
fi

init_home
install_apt

if ! command -v curl >/dev/null 2>&1; then
  warn "curl 未安装，跳过 nvm/Node/uv 安装"
else
  install_nvm_and_node
  install_uv
fi

init_project

sudo chown -R coder:coder "$PROJECT_DIR" 2>/dev/null || true

log ""
log "========================================"
log "  开发环境已就绪!"
log "  项目目录: $PROJECT_DIR"
log "  完成时间: $(date)"
log "========================================"
