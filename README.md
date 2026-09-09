# Neovim Development Container (devcontainer-nvim)

Project-independent Docker-based development environment running Neovim, Fish, Tmux, and a C++ base-toolchain-image directly inside Linux.

NOTE: This is specifically tailored to my development setup and use-case.
It makes a lot of assumptions about the host and base-toolchain-images that
won't match outside of my setup.

## Features

- **Full In-Container Toolchain:** Clang 22, Clangd LSP, LLDB (`lldb-dap`), GDB, and CMake inside the container, giving full visibility into Linux system libraries and headers.
- **Latest Fish & Neovim:** Built directly from official GitHub releases with standalone multi-arch binaries.
- **Fish & Tmux Integration:** Initial run automatically copies host configurations from `~/.config/fish`, `~/.config/tmux`, and `~/.config/nvim` into the container config volume, allowing custom in-container tweaks without affecting the macOS host.
- **Isolated Linux Environment:** Dedicated Docker named volumes (`devcontainer_local`, `devcontainer_config`, `devcontainer_cache`, `devcontainer_cursor`) isolate all `.local`, `.config`, `.cache`, and `.cursor` directories (such as Treesitter `.so` parsers, Mason binaries, shell data, and Cursor CLI state) from macOS binaries.
- **Clean Project Mounts:** Always mounts `$HOME/projects` as well as the current project working directory, Git root, and essential configs (`.gitconfig`, `.ssh`).
- **Compiler Variants:** Configurable via `VARIANTS` in `settings.env` (defaults: `clang`, `clang-tsan`, and `gcc`).
- **Project Independent:** Can be placed in `PATH` (e.g. `~/.local/bin/`) and launched from any project folder.

---

## Quick Start

### 1. Build the Images

Run the build script to create the container images for your architecture (`aarch64` or `x86_64`):

```bash
# Build the default clang variant
./tools/docker/devcontainer/build-devcontainer.sh clang

# Or build all configured variants (clang, clang-tsan, gcc)
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

# Use GCC variant
start-dev-container --gcc

# Rebuild container image
start-dev-container --re-build

# Enable bash tracing
start-dev-container --verbose

# Stop the running container for the current directory
start-dev-container --stop

# Mount the host Docker socket (run docker from inside the container)
start-dev-container --docker

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

- **Compiler Variants:** Configure available toolchain variants in the `VARIANTS` array (e.g. `clang`, `clang-tsan`, `gcc`).
- **Base Images & Registry:** Change `REGISTRY` or provide a global `BASE_IMAGE` override. Control automated image pulling with `PULL_BASE_IMAGE`.
- **Default Variant & Mode:** Set `DEFAULT_CONTAINER_VARIANT="clang"` and `DEFAULT_SHELL_MODE="tmux"`.
- **Docker Run Arguments:** Customize `DOCKER_RUN_BASE_ARGS` or add custom flags (e.g. port forwards, GPU flags) to `DOCKER_RUN_EXTRA_ARGS`. Set `MOUNT_DOCKER_SOCKET=true` (or pass `--docker`) to bind-mount the host Docker socket and run containers from inside the devcontainer.
- **Volumes & Mounts:** Configure isolated Docker volumes and host mounts in `VOLUMES`, or customize `PROJECTS_DIR`. All named volumes are auto-created and initialized with proper user ownership.
- **Compilers & Sanitizers:** Adjust `DEFAULT_CC`, `DEFAULT_CXX`, `DEV_TIMEZONE`, `ASAN_OPTIONS`, and `TSAN_OPTIONS`.

Override the settings file location by setting the `DEVCONTAINER_SETTINGS_FILE` environment variable.

---

## Command Reference

```
Usage: start-dev-container [OPTIONS] [-- COMMAND...]

Variants (configured in settings.env):
  -v, --variant VAR  Specify variant explicitly (default: clang)
  --clang            Use clang toolchain variant
  --clang-tsan       Use clang-tsan toolchain variant
  --gcc              Use gcc toolchain variant

Modes:
  --tmux             Start inside a tmux session (default)
  --fish             Start directly into fish shell
  --nvim             Start directly into Neovim
  -c, --command CMD  Run custom command inside container

Options:
  --init-config      Copy host fish, tmux, and Neovim configs into the config volume
  --stop             Stop the running devcontainer for the current directory
  --re-build         Rebuild the container image before starting (pulls latest base image)
  --no-pull          Do not pull base image when rebuilding
  --verbose          Enable bash tracing (set -x)
  -e KEY=VAL         Pass additional environment variable
  --root             Run container directly as root (default: match host user)
  --docker           Mount the host Docker socket (run containers from inside)
  --no-docker        Do not mount the Docker socket (overrides settings.env)
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
| `build-devcontainer.sh` | Builds the Docker images (any configured variant, or `all`) |
| `start-dev-container` | Project-independent launcher script to mount configs and start container |
| `attach-dev-container` | Script to attach to running devcontainer with new fish shell and container picker |
