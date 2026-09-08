ARG BASE_IMAGE=registry.example.com/toolchain/trixie/aarch64/clang-22.1.8/main
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# Install essential CLI tools, shells, and utilities
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
    bpython \
    ca-certificates \
    curl \
    delta \
    direnv \
    fd-find \
    fzf \
    git \
    git-lfs \
    gosu \
    gzip \
    kitty-terminfo \
    lazygit \
    less \
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
    tmux \
    unzip \
    wget \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Symlink cc/c++ to clang/clang++ and fd to fdfind
RUN ln -sf /usr/local/bin/clang /usr/local/bin/cc && \
    ln -sf /usr/local/bin/clang++ /usr/local/bin/c++ && \
    ln -sf /usr/bin/fdfind /usr/local/bin/fd && \
    printf '#!/bin/sh\nexit 0\n' > /usr/local/bin/kitty && \
    chmod +x /usr/local/bin/kitty

# Install cppman for C++ documentation in Neovim (<leader>cp)
RUN python3 -m pip install --break-system-packages --ignore-installed typing_extensions cppman || true

# Install latest Fish shell from GitHub release
RUN set -ex; \
    ARCH="$(uname -m)"; \
    case "${ARCH}" in \
    aarch64|arm64) FISH_ARCH="aarch64" ;; \
    x86_64|amd64)  FISH_ARCH="x86_64" ;; \
    *) echo "Unsupported architecture: ${ARCH}" >&2; exit 1 ;; \
    esac; \
    FISH_VERSION="$(curl -sIL https://github.com/fish-shell/fish-shell/releases/latest | tr -d '\r' | awk -F'/tag/' '/^[Ll]ocation:/ {print $2}')"; \
    [ -n "${FISH_VERSION}" ] || { echo "Failed to determine latest fish version" >&2; exit 1; }; \
    echo "Installing fish ${FISH_VERSION} for ${FISH_ARCH}..."; \
    mkdir -p /tmp/fish-install; \
    curl -sSL "https://github.com/fish-shell/fish-shell/releases/download/${FISH_VERSION}/fish-${FISH_VERSION}-linux-${FISH_ARCH}.tar.xz" \
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

# Install latest Neovim from GitHub release
RUN set -ex; \
    ARCH="$(uname -m)"; \
    case "${ARCH}" in \
    aarch64|arm64) NVIM_ARCH="arm64" ;; \
    x86_64|amd64)  NVIM_ARCH="x86_64" ;; \
    *) echo "Unsupported architecture: ${ARCH}" >&2; exit 1 ;; \
    esac; \
    mkdir -p /opt/nvim; \
    curl -sSL "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${NVIM_ARCH}.tar.gz" \
    | tar -xz -C /opt/nvim --strip-components=1; \
    ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim; \
    /usr/local/bin/nvim --version | head -2


# insatll uv
RUN set -ex; \
    curl -LsSf https://astral.sh/uv/install.sh | sh \
    && mv /root/.local/bin/u* /usr/bin/

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["fish"]
