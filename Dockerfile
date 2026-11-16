ARG BASE_IMAGE=registry.example.com/toolchain/trixie/aarch64/clang-22.1.8/main
FROM ${BASE_IMAGE}

# Pinned tool versions. Bump deliberately when upgrading the toolchain.
ARG CPPMAN_VERSION=0.6.3
ARG FISH_VERSION=4.9.3
ARG NVIM_VERSION=0.12.6
ARG TMUX_VERSION=3.8
ARG UV_VERSION=0.13.7
ARG GO_VERSION=1.27.4
ARG DOCKER_VERSION=29.9.3
ARG GRPCURL_VERSION=1.9.4
ARG CODELLDB_VERSION=1.12.3

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# Install essential CLI tools, shells, and utilities
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
    bpython \
    bubblewrap \
    ca-certificates \
    curl \
    direnv \
    fd-find \
    fzf \
    git \
    git-delta \
    git-lfs \
    gosu \
    groff \
    gzip \
    htop \
    jq \
    kitty-terminfo \
    lazygit \
    less \
    libgcc-s1 \
    libstdc++6 \
    luarocks \
    most \
    ncurses-term \
    nodejs \
    npm \
    openjdk-25-jdk \
    procps \
    python3 \
    python3-pip \
    python3-venv \
    ripgrep \
    sudo \
    tar \
    thefuck \
    unzip \
    wget \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Symlink cc/c++ to detected toolchain and fd to fdfind
RUN if [ -f /usr/local/bin/clang ]; then \
    ln -sf /usr/local/bin/clang /usr/local/bin/cc && \
    ln -sf /usr/local/bin/clang++ /usr/local/bin/c++; \
    elif [ -f /usr/local/bin/gcc ]; then \
    ln -sf /usr/local/bin/gcc /usr/local/bin/cc && \
    ln -sf /usr/local/bin/g++ /usr/local/bin/c++; \
    fi && \
    ln -sf /usr/bin/fdfind /usr/local/bin/fd && \
    printf '#!/bin/sh\nexit 0\n' > /usr/local/bin/kitty && \
    chmod +x /usr/local/bin/kitty

# Install cppman for C++ documentation in Neovim (<leader>cp)
RUN python3 -m pip install --break-system-packages --ignore-installed typing_extensions "cppman==${CPPMAN_VERSION}" || true

# Install Fish shell from GitHub release
RUN set -ex; \
    ARCH="$(uname -m)"; \
    case "${ARCH}" in \
    aarch64|arm64) FISH_ARCH="aarch64" ;; \
    x86_64|amd64)  FISH_ARCH="x86_64" ;; \
    *) echo "Unsupported architecture: ${ARCH}" >&2; exit 1 ;; \
    esac; \
    echo "Installing fish ${FISH_VERSION} for ${FISH_ARCH}..."; \
    mkdir -p /tmp/fish-install; \
    curl -fsSL "https://github.com/fish-shell/fish-shell/releases/download/${FISH_VERSION}/fish-${FISH_VERSION}-linux-${FISH_ARCH}.tar.xz" \
    | tar -xJ -C /tmp/fish-install; \
    mv /tmp/fish-install/fish /usr/local/bin/fish; \
    ln -sf /usr/local/bin/fish /usr/local/bin/fish_indent; \
    ln -sf /usr/local/bin/fish /usr/local/bin/fish_key_reader; \
    ln -sf /usr/local/bin/fish /usr/bin/fish; \
    ln -sf /usr/local/bin/fish /usr/bin/fish_indent; \
    ln -sf /usr/local/bin/fish /usr/bin/fish_key_reader; \
    rm -rf /tmp/fish-install; \
    grep -qxF "/usr/local/bin/fish" /etc/shells 2>/dev/null || echo "/usr/local/bin/fish" >> /etc/shells; \
    grep -qxF "/usr/bin/fish" /etc/shells 2>/dev/null || echo "/usr/bin/fish" >> /etc/shells; \
    /usr/local/bin/fish --version

# Install Neovim from GitHub release
RUN set -ex; \
    ARCH="$(uname -m)"; \
    case "${ARCH}" in \
    aarch64|arm64) NVIM_ARCH="arm64" ;; \
    x86_64|amd64)  NVIM_ARCH="x86_64" ;; \
    *) echo "Unsupported architecture: ${ARCH}" >&2; exit 1 ;; \
    esac; \
    echo "Installing Neovim ${NVIM_VERSION} for linux-${NVIM_ARCH}..."; \
    mkdir -p /opt/nvim; \
    curl -fsSL "https://github.com/neovim/neovim/releases/download/v${NVIM_VERSION}/nvim-linux-${NVIM_ARCH}.tar.gz" \
    | tar -xz -C /opt/nvim --strip-components=1; \
    ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim; \
    /usr/local/bin/nvim --version | head -2

# Build latest tmux from source
RUN set -ex; \
    apt-get update -qq; \
    apt-get install -y -qq --no-install-recommends \
    bison \
    libevent-dev \
    libncurses-dev \
    make \
    pkg-config; \
    echo "Installing tmux ${TMUX_VERSION}..."; \
    mkdir -p /tmp/tmux-build; \
    curl -fsSL "https://github.com/tmux/tmux/releases/download/${TMUX_VERSION}/tmux-${TMUX_VERSION}.tar.gz" \
    | tar -xz -C /tmp/tmux-build --strip-components=1; \
    cd /tmp/tmux-build; \
    ./configure --prefix=/usr/local >/dev/null; \
    make -j"$(nproc)" >/dev/null; \
    make install; \
    cd /; rm -rf /tmp/tmux-build /var/lib/apt/lists/*; \
    /usr/local/bin/tmux -V


# Install uv
RUN set -ex; \
    curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" | sh \
    && mv /root/.local/bin/u* /usr/bin/ \
    && uv --version

# Install Go from go.dev
RUN set -ex; \
    ARCH="$(uname -m)"; \
    case "${ARCH}" in \
    aarch64|arm64) GO_ARCH="arm64" ;; \
    x86_64|amd64)  GO_ARCH="amd64" ;; \
    *) echo "Unsupported architecture: ${ARCH}" >&2; exit 1 ;; \
    esac; \
    echo "Installing Go ${GO_VERSION} for linux-${GO_ARCH}..."; \
    rm -rf /usr/local/go; \
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" \
    | tar -C /usr/local -xz; \
    ln -sf /usr/local/go/bin/go /usr/local/bin/go; \
    ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt; \
    /usr/local/bin/go version

# Install Docker CLI (client only) so a mounted host socket can start containers
RUN set -ex; \
    ARCH="$(uname -m)"; \
    case "${ARCH}" in \
    aarch64|arm64) DOCKER_ARCH="aarch64" ;; \
    x86_64|amd64)  DOCKER_ARCH="x86_64" ;; \
    *) echo "Unsupported architecture: ${ARCH}" >&2; exit 1 ;; \
    esac; \
    echo "Installing Docker CLI ${DOCKER_VERSION} for linux-${DOCKER_ARCH}..."; \
    curl -fsSL "https://download.docker.com/linux/static/stable/${DOCKER_ARCH}/docker-${DOCKER_VERSION}.tgz" \
    | tar -xz -C /usr/local/bin --strip-components=1 docker/docker; \
    /usr/local/bin/docker --version

# Install grpcurl via go
RUN set -ex; \
    GOBIN=/usr/local/bin /usr/local/bin/go install "github.com/fullstorydev/grpcurl/cmd/grpcurl@v${GRPCURL_VERSION}"; \
    /usr/local/bin/grpcurl -version

# Install CodeLLDB native debug adapter
RUN set -ex; \
    ARCH="$(uname -m)"; \
    case "${ARCH}" in \
    aarch64|arm64) CODELLDB_ARCH="arm64" ;; \
    x86_64|amd64)  CODELLDB_ARCH="x64" ;; \
    *) echo "Unsupported architecture: ${ARCH}" >&2; exit 1 ;; \
    esac; \
    echo "Installing CodeLLDB ${CODELLDB_VERSION} for linux-${CODELLDB_ARCH}..."; \
    curl --fail --location --retry 3 \
    "https://github.com/vadimcn/codelldb/releases/download/v${CODELLDB_VERSION}/codelldb-linux-${CODELLDB_ARCH}.vsix" \
    --output /tmp/codelldb.vsix; \
    mkdir -p /opt/codelldb; \
    unzip -q /tmp/codelldb.vsix 'extension/*' -d /opt/codelldb; \
    chmod +x /opt/codelldb/extension/adapter/codelldb; \
    ln -s /opt/codelldb/extension/adapter/codelldb /usr/local/bin/codelldb; \
    rm /tmp/codelldb.vsix; \
    test -x /usr/local/bin/codelldb

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["fish"]
