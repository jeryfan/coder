#!/usr/bin/env bash
set -euo pipefail

# ── 模板变量 ──────────────────────────────────────────────
readonly SOURCE="${source}"
readonly NAME="${name}"
readonly REPO="${repo}"
readonly WORKSPACE_DIR="${workspace_dir}"
readonly PROJECT_DIR="${project_dir}"
readonly NODE_VERSION="${node_version}"
readonly NVM_VERSION="v0.40.1"

# ── 日志 ──────────────────────────────────────────────────
STEP=0
TOTAL=5

log()  { printf '%s\n' "$*"; }
step() { STEP=$((STEP + 1)); log "[$STEP/$TOTAL] $*"; }
warn() { printf '警告: %s\n' "$*" >&2; }
die()  { printf '错误: %s\n' "$*" >&2; exit 1; }

# ── 初始化 HOME ──────────────────────────────────────────
init_home() {
  if [ ! -f "$HOME/.init_done" ]; then
    cp -rT /etc/skel "$HOME"
    touch "$HOME/.init_done"
  fi
  mkdir -p "$WORKSPACE_DIR"
}

# ── 安装系统依赖 ─────────────────────────────────────────
install_apt() {
  step "安装系统依赖..."
  if [ -f "$HOME/.apt_done" ]; then
    log "  已完成，跳过"
    return
  fi
  export DEBIAN_FRONTEND=noninteractive
  if sudo apt-get update -qq 2>/dev/null; then
    sudo apt-get install -y -qq python3-venv git vim curl wget unzip 2>/dev/null
    touch "$HOME/.apt_done"
  else
    warn "apt-get update 失败，跳过系统依赖安装"
  fi
}

# ── 配置 code-server 中文界面 ────────────────────────────
configure_code_server() {
  step "配置 code-server 中文界面..."
  local config_dir="$HOME/.config/code-server"
  local user_data_dir="$HOME/.local/share/code-server/User"
  local argv_file="$user_data_dir/argv.json"

  mkdir -p "$config_dir" "$user_data_dir"

  if ! grep -q '^locale:' "$config_dir/config.yaml" 2>/dev/null; then
    echo 'locale: zh-cn' >> "$config_dir/config.yaml"
  fi

  if [ ! -f "$argv_file" ]; then
    echo '{ "locale": "zh-cn" }' > "$argv_file"
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$argv_file" <<'PY'
import json, sys
path = sys.argv[1]
try:
    with open(path) as f:
        data = json.load(f)
except Exception:
    data = {}
if data.get("locale") != "zh-cn":
    data["locale"] = "zh-cn"
    with open(path, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
PY
  fi
}

# ── 安装 Node.js (nvm) ──────────────────────────────────
install_node() {
  step "安装 Node.js (nvm)..."
  export NVM_DIR="$HOME/.nvm"

  if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh" | bash
  fi

  if ! grep -q 'NVM_DIR' "$HOME/.bashrc" 2>/dev/null; then
    cat >> "$HOME/.bashrc" <<'BASH'
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
BASH
  fi

  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

  if command -v nvm >/dev/null 2>&1; then
    nvm install "$NODE_VERSION"
    nvm alias default "$NODE_VERSION"
  else
    warn "nvm 未就绪，跳过 Node 安装"
  fi
}

# ── 安装 uv ──────────────────────────────────────────────
install_uv() {
  step "安装 uv..."
  local bin_dir="$HOME/.local/bin"
  mkdir -p "$bin_dir"

  if [ ! -x "$bin_dir/uv" ]; then
    curl -LsSf https://astral.sh/uv/install.sh \
      | UV_INSTALL_DIR="$bin_dir" UV_NO_MODIFY_PATH=1 sh
  fi

  export PATH="$bin_dir:$PATH"
  if ! grep -q '/.local/bin' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
  fi

  # 配置国内镜像源
  local uv_config_dir="$HOME/.config/uv"
  if [ ! -f "$uv_config_dir/uv.toml" ]; then
    mkdir -p "$uv_config_dir"
    cat > "$uv_config_dir/uv.toml" <<'TOML'
index-url = "https://mirrors.aliyun.com/pypi/simple/"
TOML
  fi
}

# ── 初始化项目 ───────────────────────────────────────────
init_project() {
  step "初始化项目..."
  cd "$WORKSPACE_DIR"

  if [ -d "$PROJECT_DIR" ]; then
    log "  项目目录已存在，跳过"
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
        [ -f scrapy.cfg ] || uv run scrapy startproject "$NAME" .
      else
        mkdir -p "$PROJECT_DIR"
        cat > "$PROJECT_DIR/README.md" <<'MD'
# Scrapy 项目初始化失败

环境中未安装 uv，请手动执行以下命令：

```bash
cd ~/workspace
uv init <项目名>
cd <项目名>
uv add scrapy
uv run scrapy startproject <项目名> .
```
MD
      fi
      ;;
    git)
      git clone --depth 1 "$REPO" "$PROJECT_DIR"
      ;;
  esac
}

# ── 主流程 ───────────────────────────────────────────────
main() {
  log "========================================"
  log "  爬虫开发环境初始化"
  log "  项目来源: $SOURCE"
  log "  项目名称: $NAME"
  log "  开始时间: $(date)"
  log "========================================"

  if [ "$SOURCE" = "git" ] && [ -z "$REPO" ]; then
    die "选择了 Git 仓库来源但未提供仓库地址"
  fi

  init_home
  install_apt
  configure_code_server

  if command -v curl >/dev/null 2>&1; then
    install_node
    install_uv
  else
    warn "curl 未安装，跳过 Node/uv 安装"
    STEP=$((STEP + 2))
  fi

  init_project

  sudo chown -R coder:coder "$PROJECT_DIR" 2>/dev/null || true

  log ""
  log "========================================"
  log "  开发环境已就绪!"
  log "  项目目录: $PROJECT_DIR"
  log "  完成时间: $(date)"
  log "========================================"
}

main "$@"
