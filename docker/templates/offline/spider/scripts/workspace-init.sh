#!/usr/bin/env bash
set -euo pipefail

# ── 模板变量 ──────────────────────────────────────────────
readonly SOURCE="${source}"
readonly NAME="${name}"
readonly WORKSPACE_DIR="${workspace_dir}"
readonly PROJECT_DIR="${project_dir}"

# ── 日志 ──────────────────────────────────────────────────
STEP=0
TOTAL=2

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

# ── 初始化项目（离线模式）────────────────────────────────
init_project() {
  step "初始化项目..."
  cd "$WORKSPACE_DIR"

  if [ -d "$PROJECT_DIR" ]; then
    log "  项目目录已存在，跳过"
    return
  fi

  export PATH="$HOME/.local/bin:$PATH"

  case "$SOURCE" in
    empty)
      mkdir -p "$PROJECT_DIR"
      ;;
    scrapy)
      if command -v uv >/dev/null 2>&1; then
        uv init "$NAME"
        cd "$PROJECT_DIR"
        uv add scrapy --offline
        [ -f scrapy.cfg ] || uv run --offline scrapy startproject "$NAME" .
      else
        mkdir -p "$PROJECT_DIR"
        warn "uv 未安装，无法初始化 Scrapy 项目"
      fi
      ;;
  esac
}

# ── 主流程 ───────────────────────────────────────────────
main() {
  log "========================================"
  log "  爬虫开发环境初始化（离线模式）"
  log "  项目来源: $SOURCE"
  log "  项目名称: $NAME"
  log "  开始时间: $(date)"
  log "========================================"

  init_home
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
