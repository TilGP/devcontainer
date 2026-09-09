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

    # If the host Docker socket is mounted, grant the container user access
    if [ -S /var/run/docker.sock ]; then
        sock_gid="$(stat -c '%g' /var/run/docker.sock 2>/dev/null || echo 0)"
        sock_uid="$(stat -c '%u' /var/run/docker.sock 2>/dev/null || echo 0)"
        if [ "$sock_gid" != "0" ]; then
            if ! getent group "$sock_gid" >/dev/null 2>&1; then
                groupadd -g "$sock_gid" docker-host 2>/dev/null || true
            fi
            sock_grp="$(getent group "$sock_gid" | cut -d: -f1)"
            [ -n "$sock_grp" ] && usermod -aG "$sock_grp" "$DEV_USER" 2>/dev/null || true
        elif [ "$sock_uid" != "$DEV_UID" ]; then
            # Docker Desktop often exposes the socket as root:root; make it usable
            chmod 666 /var/run/docker.sock 2>/dev/null || true
        fi
    fi
    mkdir -p /etc/sudoers.d
    # Note: sudoers.d filenames containing '.' or '~' are ignored by sudo (@includedir /etc/sudoers.d)
    echo "$DEV_USER ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers.d/nopasswd
    echo "%sudo ALL=(ALL:ALL) NOPASSWD:ALL" >> /etc/sudoers.d/nopasswd
    chmod 0440 /etc/sudoers.d/nopasswd

    # Ensure home and standard local subdirectories exist
    mkdir -p "$DEV_HOME/.local/bin" "$DEV_HOME/.local/share" "$DEV_HOME/.local/state" 2>/dev/null || true
    chown "$DEV_UID:$DEV_GID" "$DEV_HOME" 2>/dev/null || true

    # Fix ownership for configured volume directories
    if [ -n "$DEV_CHOWN_DIRS" ]; then
        for chdir in $DEV_CHOWN_DIRS; do
            [ -d "$chdir" ] && chown -R "$DEV_UID:$DEV_GID" "$chdir" 2>/dev/null || true
        done
    fi

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
    export GOPATH="${GOPATH:-$DEV_HOME/go}"
    export PATH="$DEV_HOME/.local/bin:$GOPATH/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
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

    export GOPATH="${GOPATH:-/root/go}"
    export PATH="/root/.local/bin:$GOPATH/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
    export EDITOR="${EDITOR:-nvim}"
    export VISUAL="${VISUAL:-nvim}"
    exec "$@"
fi
