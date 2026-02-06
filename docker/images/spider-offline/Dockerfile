FROM codercom/enterprise-base:ubuntu

USER root

# ── 系统依赖 ──────────────────────────────────────────────
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
        python3-venv python3-pip git vim curl wget unzip && \
    rm -rf /var/lib/apt/lists/*

# ── code-server（系统级）──────────────────────────────────
RUN curl -fsSL https://code-server.dev/install.sh | sh

# ── filebrowser（系统级）──────────────────────────────────
RUN curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash

USER coder

# ── nvm + Node.js LTS ────────────────────────────────────
ENV NVM_DIR="/home/coder/.nvm"
ENV NVM_VERSION="v0.40.1"

RUN curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash && \
    . "$NVM_DIR/nvm.sh" && \
    nvm install --lts && \
    nvm alias default lts/* && \
    echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.bashrc && \
    echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> ~/.bashrc && \
    echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' >> ~/.bashrc

# ── uv + 阿里云 PyPI 镜像 ────────────────────────────────
RUN curl -LsSf https://astral.sh/uv/install.sh | \
        UV_INSTALL_DIR="/home/coder/.local/bin" UV_NO_MODIFY_PATH=1 sh && \
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && \
    mkdir -p ~/.config/uv && \
    printf 'index-url = "https://mirrors.aliyun.com/pypi/simple/"\n' > ~/.config/uv/uv.toml

# ── 预安装 JupyterLab ────────────────────────────────────
RUN export PATH="$HOME/.local/bin:$PATH" && \
    uv tool install jupyterlab

# ── 预缓存 Scrapy 依赖 ───────────────────────────────────
RUN export PATH="$HOME/.local/bin:$PATH" && \
    cd /tmp && uv init scrapy_cache && cd scrapy_cache && \
    uv add scrapy && \
    cd / && rm -rf /tmp/scrapy_cache

# ── 预安装 code-server 扩展 ──────────────────────────────
RUN code-server --install-extension ms-python.python
