# Neovim Development Container (devcontainer-nvim)

Project-independent Docker-based development environment running Neovim, Fish, Tmux, and the Clang toolchain directly inside Linux.

## Features

- **Full In-Container Toolchain:** Clang 22, Clangd LSP, LLDB (`lldb-dap`), GDB, and CMake inside the container, giving full visibility into Linux system libraries and headers.
- **Latest Fish & Neovim:** Built directly from official GitHub releases with standalone multi-arch binaries.
- **Fish & Tmux Integration:** Initial run automatically copies host configurations from `~/.config/fish`, `~/.config/tmux`, and `~/.config/nvim` into the container config volume, allowing custom in-container tweaks without affecting the macOS host.
- **Isolated Linux Environment:** Host `$HOME` is no longer mounted entirely. Instead, dedicated Docker named volumes (`devcontainer_local`, `devcontainer_config`, `devcontainer_cache`) isolate all `.local`, `.config`, and `.cache` directories (such as Treesitter `.so` parsers, Mason binaries, and shell data) from macOS binaries.
- **Clean Project Mounts:** Always mounts `$HOME/projects` as well as the current project working directory, Git root, and essential configs (`.gitconfig`, `.ssh`).
- **Compiler Variants:** Provides `clang`, `clang-tsan` (ThreadSanitizer-instrumented), and `clang++`.
- **Project Independent:** Can be placed in `PATH` (e.g. `~/.local/bin/`) and launched from any project folder.

---

## Quick Start

### 1. Build the Images

Run the build script to create the container images for your architecture (`aarch64` or `x86_64`):

```bash
# Build the default clang variant
./tools/docker/devcontainer/build-devcontainer.sh clang

# Or build all variants (clang, clang-tsan, clang++)
./tools/docker/devcontainer/build-devcontainer.sh all
```

### 2. Put Scripts in your PATH

Symlink or copy the launcher and attach scripts into your local bin directory:

```bash
ln -sf "$(pwd)/start-dev-container" ~/.local/bin/start-dev-container
ln -sf "$(pwd)/attach-dev-container" ~/.local/bin/attach-dev-container
ln -sf "$(pwd)/attach-dev-container" ~/.local/bin/attach-to-devcontainer
```

*(Ensure `~/.local/bin` is in your `PATH`.)*

### 3. Launching

From any project directory:

```bash
# Start inside Tmux session with Fish shell (default)
start-dev-container

# Start directly in Neovim
start-dev-container --nvim

# Start directly in Fish shell
start-dev-container --fish

# Use TSan variant
start-dev-container --clang-tsan

# Use Clang++ variant
start-dev-container --clang++

# Rebuild container image
start-dev-container --re-build

# Enable bash tracing
start-dev-container --verbose

# Stop the running container for the current directory
start-dev-container --stop

# Run an arbitrary command inside the container (runs foreground)
start-dev-container -- make -j8
start-dev-container -c "cmake --build cmake-build-debug"
```

When started without an explicit command, `start-dev-container` runs the container in the background (`-d`) with `sleep infinity` and attaches via `attach-dev-container`. This ensures that logging out or closing your terminal session will not terminate the container or kill other attached sessions. You can reconnect anytime by running `start-dev-container` or `attach-dev-container`.

### 4. Attaching to Running Devcontainers

From any terminal:

```bash
# Auto-attach to single running devcontainer, or open picker if multiple
attach-dev-container

# Or use alias:
attach-to-devcontainer

# Attach directly to a specific container
attach-dev-container my-container

# Attach as root
attach-dev-container --root
```

---

## Configuration (`settings.env`)

Configuration is managed via `settings.env`. Create your local configuration file from the template:

```bash
cp settings.env.dist settings.env
```

You can customize the devcontainer environment by editing `settings.env` directly:

- **Base Images & Registry:** Change `REGISTRY`, `BASE_IMAGE_CLANG`, `BASE_IMAGE_CLANG_TSAN`, `BASE_IMAGE_CLANGPP`, or provide a global `BASE_IMAGE`.
- **Image Names & Tags:** Adjust `IMAGE_TAG_CLANG`, `IMAGE_TAG_CLANG_TSAN`, `IMAGE_TAG_CLANGPP`.
- **Default Variant & Mode:** Set `DEFAULT_CONTAINER_VARIANT="clang"` and `DEFAULT_SHELL_MODE="tmux"`.
- **Docker Run Arguments:** Customize `DOCKER_RUN_BASE_ARGS` or add custom flags (e.g. port forwards, GPU flags) to `DOCKER_RUN_EXTRA_ARGS`.
- **Volumes & Mounts:** Change `VOLUME_LOCAL`, `VOLUME_CONFIG`, `VOLUME_CACHE`, or `PROJECTS_DIR`.
- **Compilers & Sanitizers:** Adjust `DEFAULT_CC`, `DEFAULT_CXX`, `DEV_TIMEZONE`, `ASAN_OPTIONS`, and `TSAN_OPTIONS`.

Override the settings file location by setting the `DEVCONTAINER_SETTINGS_FILE` environment variable.

---

## Command Reference

```
Usage: start-dev-container [OPTIONS] [-- COMMAND...]

Variants:
  --clang            Use standard Clang toolchain (default)
  --clang-tsan       Use TSan-instrumented Clang toolchain
  --clang++          Use Clang C++ toolchain (sets CXX=clang++)
  -v, --variant VAR  Specify variant explicitly: clang, clang-tsan, clang++, clangpp

Modes:
  --tmux             Start inside a tmux session (default)
  --fish             Start directly into fish shell
  --nvim             Start directly into Neovim
  -c, --command CMD  Run custom command inside container

Options:
  --init-config      Copy host fish, tmux, and Neovim configs into the config volume
  --stop             Stop the running devcontainer for the current directory
  --re-build         Rebuild the container image before starting
  --verbose          Enable bash tracing (set -x)
  -e KEY=VAL         Pass additional environment variable
  --root             Run container directly as root (default: match host user)
  -w DIR             Set custom working directory inside container
  --name NAME        Set container name
  -h, --help         Show help message
```

---

## File Structure

| File | Description |
|---|---|
| `settings.env.dist` | Template configuration file for base images, image tags, docker run args, and volumes |
| `settings.env` | Local configuration file (gitignored, copied from `settings.env.dist`) |
| `Dockerfile` | Multi-arch container definition with Neovim, Fish, Tmux, and dev utilities |
| `entrypoint.sh` | Container entrypoint configuring dynamic user, UID/GID, sudo, and permissions |
| `build-devcontainer.sh` | Builds the Docker images (`clang`, `clang-tsan`, `clang++`, or `all`) |
| `start-dev-container` | Project-independent launcher script to mount configs and start container |
| `attach-dev-container` | Script to attach to running devcontainer with new fish shell and container picker |
