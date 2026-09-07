#!/usr/bin/env bash
set -e

# If DEV_USER is specified and not root, set up user inside container
if [ -n "$DEV_USER" ] && [ "$DEV_USER" != "root" ]; then
    DEV_UID="${DEV_UID:-1000}"
    DEV_GID="${DEV_GID:-1000}"
    DEV_HOME="${DEV_HOME:-/home/$DEV_USER}"

    # Ensure home directory exists inside container
    mkdir -p "$DEV_HOME" 2>/dev/null || true

    # Ensure group exists
    if ! getent group "$DEV_GID" >/dev/null 2>&1; then
        groupadd -g "$DEV_GID" "$DEV_USER" 2>/dev/null || true
    fi
    GRP=$(getent group "$DEV_GID" | cut -d: -f1)
    [ -z "$GRP" ] && GRP="$DEV_USER"

    # Ensure user exists
    if ! id -u "$DEV_USER" >/dev/null 2>&1; then
        useradd -u "$DEV_UID" -g "$GRP" -d "$DEV_HOME" -s /usr/local/bin/fish "$DEV_USER" 2>/dev/null || true
    else
        usermod -s /usr/local/bin/fish -d "$DEV_HOME" "$DEV_USER" 2>/dev/null || true
    fi

    # Ensure user is in sudo group with passwordless sudo
    usermod -aG sudo "$DEV_USER" 2>/dev/null || true
    mkdir -p /etc/sudoers.d
    echo "$DEV_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$DEV_USER"
    chmod 0440 "/etc/sudoers.d/$DEV_USER"

    # Ensure container-specific isolated directories exist and have proper ownership
    mkdir -p "$DEV_HOME/.local/bin" "$DEV_HOME/.local/share" "$DEV_HOME/.local/state" "$DEV_HOME/.config" "$DEV_HOME/.cache" 2>/dev/null || true
    chown "$DEV_UID:$DEV_GID" "$DEV_HOME" 2>/dev/null || true
    chown -R "$DEV_UID:$DEV_GID" "$DEV_HOME/.local" "$DEV_HOME/.cache" "$DEV_HOME/.config" 2>/dev/null || true

    # Clean up accidental ~/.tmux.conf symlink pointing to ~/.config/tmux/tmux.conf
    # which breaks Oh My Tmux when local config is in ~/.config/tmux/tmux.conf.local
    if [ -L "$DEV_HOME/.tmux.conf" ] && [ "$(readlink "$DEV_HOME/.tmux.conf" 2>/dev/null)" = "$DEV_HOME/.config/tmux/tmux.conf" ]; then
        rm -f "$DEV_HOME/.tmux.conf" 2>/dev/null || true
    fi

    # In case user genuinely has ~/.tmux.conf but their local config is in ~/.config/tmux/tmux.conf.local
    if [ -f "$DEV_HOME/.tmux.conf" ] && [ ! -f "$DEV_HOME/.tmux.conf.local" ] && [ -f "$DEV_HOME/.config/tmux/tmux.conf.local" ]; then
        ln -sf "$DEV_HOME/.config/tmux/tmux.conf.local" "$DEV_HOME/.tmux.conf.local" 2>/dev/null || true
    fi

    # Export standard environment
    export HOME="$DEV_HOME"
    export USER="$DEV_USER"
    export PATH="$DEV_HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
    export EDITOR="${EDITOR:-nvim}"
    export VISUAL="${VISUAL:-nvim}"

    # Ensure TERM has a valid terminfo entry in the container; fallback to xterm-256color if missing
    if [ -n "$TERM" ] && ! infocmp "$TERM" >/dev/null 2>&1; then
        export TERM=xterm-256color
    fi

    # Execute as DEV_USER using gosu
    exec gosu "$DEV_USER" "$@"
else
    # Ensure TERM has a valid terminfo entry in the container; fallback to xterm-256color if missing
    if [ -n "$TERM" ] && ! infocmp "$TERM" >/dev/null 2>&1; then
        export TERM=xterm-256color
    fi

    export PATH="/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
    export EDITOR="${EDITOR:-nvim}"
    export VISUAL="${VISUAL:-nvim}"
    exec "$@"
fi
