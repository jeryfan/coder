#!/usr/bin/env bash
set -euo pipefail

# ── 信号处理 ──────────────────────────────────────────────
cleanup() {
  local exit_code=$?
  if [ $exit_code -ne 0 ]; then
    printf '初始化异常退出 (exit code: %d)，请检查上方日志\n' "$exit_code" >&2
  fi
}
trap cleanup EXIT

# ── 模板变量 ──────────────────────────────────────────────
readonly SOURCE="${source}"
readonly NAME="${name}"
readonly REPO="${repo}"
readonly WORKSPACE_DIR="${workspace_dir}"
readonly PROJECT_DIR="${project_dir}"

# ── 日志 ──────────────────────────────────────────────────
STEP=0
TOTAL=3

log()  { printf '%s\n' "$*"; }
step() { STEP=$((STEP + 1)); log "[$STEP/$TOTAL] $*"; }
warn() { printf '警告: %s\n' "$*" >&2; }
die()  { printf '错误: %s\n' "$*" >&2; exit 1; }

# ── 初始化 HOME ──────────────────────────────────────────
init_home() {
  step "初始化 HOME..."
  if [ ! -f "$HOME/.init_done" ]; then
    cp -rnT /etc/skel "$HOME"
    touch "$HOME/.init_done"
  fi
  mkdir -p "$WORKSPACE_DIR"
}

# ── 配置 code-server ─────────────────────────────────────
init_code_server() {
  step "配置 code-server..."
  local settings_dir="$HOME/.local/share/code-server/User"
  local settings_file="$settings_dir/settings.json"
  if [ ! -f "$settings_file" ]; then
    mkdir -p "$settings_dir"
    cat > "$settings_file" <<'JSON'
{
  "security.workspace.trust.enabled": false
}
JSON
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

  # 确保 uv 在 PATH 中
  export PATH="$HOME/.local/bin:$PATH"

  case "$SOURCE" in
    empty)
      mkdir -p "$PROJECT_DIR"
      ;;
    scrapy)
      if command -v uv >/dev/null 2>&1; then
        log "  uv 版本: $(uv --version)"
        uv init "$NAME"
        cd "$PROJECT_DIR"
        uv add scrapy
        log "  scrapy 版本: $(uv run scrapy version)"
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
      if ! git clone --depth 1 "$REPO" "$PROJECT_DIR"; then
        die "Git 克隆失败，请检查仓库地址是否正确: $REPO。可在终端中手动重试: git clone $REPO $PROJECT_DIR"
      fi
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
  init_code_server
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
