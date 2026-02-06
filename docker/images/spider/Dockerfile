FROM codercom/enterprise-base:ubuntu

USER root

# ── 系统依赖 ──────────────────────────────────────────────
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
        python3-venv git vim curl wget unzip && \
    rm -rf /var/lib/apt/lists/*

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
