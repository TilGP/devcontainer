# Devcontainer Host Command Bridge

## Status

Design specification for implementation.

Primary environment:

```text
Host:        macOS arm64
Runtime:     OrbStack / Docker-compatible containers
Container:   Linux, Debian trixie based
Shell:       Fish
Terminal:    Kitty
Multiplexer: tmux
Editor:      Neovim
```

The implementation must integrate into the existing repository and workflow rather than creating a separate standalone project unless there is a compelling implementation reason.

---

# 1. Objective

Add a controlled mechanism that allows programs running inside the Linux devcontainer to request selected operations from the logged-in macOS host.

Primary initial use case:

```text
container -> host -> osascript
```

Example:

```sh
host-command notification \
    "Build finished" \
    "reda-engine compiled successfully"
```

The host should then execute the corresponding macOS operation in the user's graphical login session.

The mechanism must be usable transparently from:

* Fish
* tmux
* Neovim
* build scripts
* shell scripts
* coding agents
* arbitrary programs running inside the devcontainer

It must **not** expose unrestricted host shell execution.

Additionally, Fish completions for `host-command` must be generated from the CLI's actual command definitions and made available automatically inside the devcontainer.

---

# 2. Non-goals

Do not implement:

```text
host-command exec <arbitrary shell command>
```

Do not expose:

```text
/bin/sh
/bin/bash
/bin/zsh
osascript with arbitrary source text
```

as generic remote execution interfaces.

Do not rely on:

```text
docker --privileged
```

to access macOS.

The existing container may remain privileged for its development/debugging requirements, but that privilege is unrelated to this feature.

Do not mount the macOS root filesystem or full `$HOME` merely to support host commands.

Do not expose the bridge outside the local machine.

Do not compile Go code on every `start-dev-container` invocation.

Do not regenerate Fish completions on every `start-dev-container` invocation unless they are missing or demonstrably stale.

---

# 3. High-level architecture

Preferred architecture:

```text
                         macOS
┌─────────────────────────────────────────────────────┐
│                                                     │
│ launchd                                             │
│    │                                                │
│    ▼                                                │
│ devcontainer-host                                   │
│    │                                                │
│    ├── notification                                 │
│    ├── open                                         │
│    ├── reveal                                       │
│    ├── clipboard-get                                │
│    ├── clipboard-set                                │
│    └── activate                                     │
│                                                     │
│    ▲                                                │
│    │ request/response                               │
│    │                                                │
│ Unix-domain socket                                  │
│                                                     │
│ generated Fish completion file                     │
│ ~/.local/share/devcontainer/                        │
│   host-command.fish                                 │
│                                                     │
└────────────────────┬────────────────────────────────┘
                     │
                     │ socket/file bind mounts
                     │
┌────────────────────┴────────────────────────────────┐
│ Linux devcontainer                                  │
│                                                     │
│ /usr/local/bin/host-command                         │
│                                                     │
│ Fish completion mount                              │
│ .../fish/completions/host-command.fish             │
│                                                     │
│ Fish / tmux / Neovim / scripts / agents             │
└─────────────────────────────────────────────────────┘
```

The host component is a Go daemon managed by a macOS LaunchAgent.

The container component is a small Go CLI.

Both components should share protocol and CLI metadata where practical.

---

# 4. Transport decision

## 4.1 Preferred transport

Use a Unix-domain socket if OrbStack correctly supports exposing the host socket to the Linux container.

Suggested host location:

```text
$HOME/.local/run/devcontainer-host.sock
```

Suggested container location:

```text
/run/devcontainer-host.sock
```

The container should receive:

```text
DEVCONTAINER_HOST_SOCKET=/run/devcontainer-host.sock
```

The client should use that environment variable, with `/run/devcontainer-host.sock` as its default.

## 4.2 Mandatory transport feasibility test

Do **not** assume that binding a macOS Unix-domain socket directly into an OrbStack container preserves usable socket semantics.

Before implementing the full bridge, perform a minimal test:

1. Create a Unix-domain listener on macOS.
2. Bind-mount the socket path into a temporary container.
3. Connect to it from Linux.
4. Send data in both directions.
5. Verify repeated connections.
6. Verify behavior after restarting the host listener.
7. Verify behavior after restarting the container.

Record the result.

If direct Unix-socket forwarding works reliably, use it.

## 4.3 Fallback transport

If host Unix socket forwarding does not work reliably, use TCP:

```text
container
    │
    ▼
host.docker.internal:<port>
    │
    ▼
devcontainer-host
```

The server must bind only to an interface reachable locally/from containers. It must not listen publicly on all network interfaces unless there is no alternative.

Suggested configurable port:

```text
DEVCONTAINER_HOST_PORT=45831
```

The application-level protocol must remain transport-independent.

---

# 5. Security model

The devcontainer is considered trusted enough to invoke a limited set of host operations.

It is **not** considered equivalent to arbitrary shell access to the macOS account.

This distinction matters because the devcontainer may contain:

* third-party build tools
* language servers
* npm packages
* plugins
* coding agents
* project-specific scripts
* downloaded dependencies

The server must therefore implement an explicit command allowlist.

Each command:

1. has a fixed name;
2. has a typed request;
3. validates all arguments;
4. maps directly to a specific host operation;
5. does not invoke a shell;
6. must not concatenate user-controlled strings into shell command strings.

Use Go APIs such as:

```go
exec.Command(...)
```

Never use:

```go
exec.Command("sh", "-c", userInput)
```

or equivalent.

---

# 6. Initial command set

Implement:

```text
ping
notification
open
reveal
clipboard-set
clipboard-get
activate
completion
doctor
```

## `completion`

The CLI must expose completion generation:

```sh
host-command completion fish
```

The generated output must be a complete Fish completion definition suitable for saving directly as:

```text
host-command.fish
```

Example:

```sh
host-command completion fish \
    > ~/.config/fish/completions/host-command.fish
```

The generated completions must include:

* top-level commands;
* command descriptions;
* positional argument hints where useful;
* supported static values such as allowed `activate` targets;
* `completion fish`;
* `doctor`;
* global flags such as `--help` and `--version`.

Completion definitions should derive from the same command metadata used by the CLI where practical.

Do not maintain a large manually duplicated list of commands in a separate completion script.

Adding a new CLI command should ideally require no independent modification to the Fish completion generator.

---

# 7. Arbitrary AppleScript

Do not expose:

```sh
host-command osascript '<source>'
```

If another AppleScript operation is required later, add a typed host command.

---

# 8. Protocol

Use versioned newline-delimited JSON.

Each connection should initially process one request and one response.

Requests include:

```json
{
  "version": 1,
  "id": "...",
  "command": "notification",
  "args": {
    "title": "Build",
    "message": "Finished"
  }
}
```

Errors should use stable codes such as:

```text
invalid_request
unsupported_version
unknown_command
invalid_argument
permission_denied
host_command_failed
timeout
internal_error
```

---

# 9. Timeouts and limits

Suggested defaults:

```text
maximum request size:   1 MiB
request read timeout:   5 s
command timeout:        10 s
clipboard maximum:      10 MiB
```

---

# 10. Go setup — mandatory discovery phase

Go is not currently installed in the devcontainer.

Before modifying the Docker image, inspect the existing macOS Go environment.

Run:

```sh
command -v go
type -a go
which -a go
go version
go env
echo "$PATH"
```

Check common managers:

```sh
brew list --versions go 2>/dev/null
brew info go 2>/dev/null

mise current 2>/dev/null
mise ls go 2>/dev/null

asdf current golang 2>/dev/null

goenv version 2>/dev/null
goenv versions 2>/dev/null
```

Inspect relevant configuration:

```text
~/.config/go/
~/.config/fish/
~/.tool-versions
~/.mise.toml
~/go/
```

Search for:

```sh
rg -n \
    'GOROOT|GOPATH|GOBIN|GOMODCACHE|GOCACHE|goenv|golang|mise|asdf' \
    ~/.config/fish \
    ~/.config 2>/dev/null
```

Inspect:

```sh
go env GOPATH
go env GOBIN
go env GOROOT
go env GOMODCACHE
go env GOCACHE
go env GOENV
go env GOFLAGS
go env GOPROXY
go env GOPRIVATE
go env GONOSUMDB
```

Do not dump secrets into commits or logs.

## Version selection

Use the same major/minor Go version as the host unless a clear reason exists not to.

Do not blindly use Debian's packaged Go version if it differs materially.

Prefer an explicit version:

```dockerfile
ARG GO_VERSION=<discovered-version>
```

## Container requirements

Go must:

* support arm64 and amd64;
* provide `go` and `gofmt`;
* work for the non-root development user;
* not share macOS build caches directly with Linux;
* keep platform-specific artifacts separate.

Do not mount host `GOROOT`, `GOCACHE`, or `GOMODCACHE`.

## `gopls`

Inspect the current Neovim/LazyVim configuration first.

Determine whether `gopls` is managed by:

* the image;
* Mason;
* another existing mechanism.

Avoid installing duplicate competing versions.

---

# 11. Build and generated-artifact lifecycle

This section is mandatory.

## 11.1 Go binaries must not compile during normal container startup

`start-dev-container` must **not** normally run:

```sh
go build ...
```

for either binary.

Normal startup should involve:

```text
configuration
mount setup
container lookup/start
attach
```

—not source compilation.

### Host daemon

`devcontainer-host` is compiled when:

```sh
./host/install-host-bridge
```

is run.

The installer owns:

```text
build
install
LaunchAgent update
completion generation
```

If host bridge source changes, the developer explicitly reruns:

```sh
./host/install-host-bridge
```

The installer should be fast and idempotent.

### Container client

`host-command` is compiled as part of the Docker image build.

Changing its Go source therefore requires rebuilding the image, using the existing devcontainer image build/rebuild workflow.

Do not silently compile a replacement client into a running container from `start-dev-container`.

This keeps the image reproducible.

## 11.2 Optional stale-version detection

It is desirable, but not required initially, for:

```sh
host-command doctor
```

to compare:

```text
client version
daemon version
protocol version
```

If the binaries are incompatible, produce a useful diagnostic.

`start-dev-container` may perform a lightweight compatibility check if that proves inexpensive, but it must not automatically rebuild binaries.

A message such as:

```text
Host bridge client/daemon versions differ.
Run ./host/install-host-bridge and rebuild the devcontainer image.
```

is preferable to hidden compilation.

---

# 12. Fish completion lifecycle

Fish completions are a generated artifact.

Suggested host location:

```text
$HOME/.local/share/devcontainer/host-command.fish
```

Do not write them directly into the macOS Fish configuration if the purpose is specifically to expose them to the container.

The host installer should generate them using:

```sh
host-command completion fish
```

or an equivalent shared Go completion generator.

Because the Linux `host-command` binary may not yet exist on the host, the installer may generate them using one of:

```sh
go run ./cmd/host-command completion fish
```

or a shared Go generation command/package.

Prefer the solution that avoids installing an otherwise unnecessary Darwin `host-command` client.

## 12.1 Mount into container

`start-dev-container` should bind-mount the generated file read-only into a Fish completion directory visible inside the container.

The exact target path must be determined from the existing Fish setup.

Candidate:

```text
/home/<container-user>/.config/fish/completions/host-command.fish
```

However, inspect the current mounted Fish configuration and `fish_complete_path` first.

Do not overwrite an existing mounted `~/.config/fish/completions` directory or conflict with dotfile mounts.

A dedicated directory is acceptable if added to Fish's completion search path.

For example:

```text
/run/devcontainer/fish-completions/host-command.fish
```

with corresponding Fish configuration if that integrates more safely.

Prefer the least invasive solution compatible with the current repository.

## 12.2 Do completions need regeneration on every startup?

Investigate this explicitly during implementation.

Expected answer: **no**.

Fish reads completion files dynamically from its completion search paths. The generated file only needs to change when the `host-command` CLI surface changes.

Therefore the normal lifecycle should be:

```text
host/install-host-bridge
        │
        ├── compile daemon
        └── generate completion file
                     │
                     ▼
~/.local/share/devcontainer/host-command.fish
                     │
                     │ read-only mount
                     ▼
              devcontainer Fish
```

`start-dev-container` should normally only mount the existing completion file.

It should not regenerate it every time.

## 12.3 Missing completion file

If the completion file does not exist, `start-dev-container` should not fail.

Possible behavior:

```text
Warning: host-command Fish completions are unavailable.
Run ./host/install-host-bridge to generate them.
```

Alternatively, omit the warning if the host bridge itself is also unavailable and a single bridge warning already covers the situation.

## 12.4 Stale completion detection

Do not regenerate blindly.

Prefer one of these approaches:

### Preferred

Embed a CLI schema/version marker in the generated completion file:

```fish
# host-command completion schema: 3
```

and expose the corresponding version from source.

The installer always regenerates the file.

Normal `start-dev-container` does not need to compare it.

### Optional

Store source/build metadata beside the generated file:

```text
~/.local/share/devcontainer/
├── host-command.fish
└── host-command.metadata
```

Only use this if it provides concrete value.

Avoid inventing a miniature build system solely to save milliseconds of completion generation. \s

---

# 13. Project layout

Prefer:

```text
devcontainer/
├── cmd/
│   ├── devcontainer-host/
│   │   └── main.go
│   └── host-command/
│       └── main.go
│
├── internal/
│   ├── protocol/
│   ├── client/
│   ├── cli/
│   │   ├── commands.go
│   │   └── completions.go
│   └── host/
│
├── host/
│   ├── dev.til.devcontainer-host.plist
│   └── install-host-bridge
│
├── Dockerfile
├── start-dev-container
├── settings.env.dist
├── go.mod
├── go.sum
└── README.md
```

Prefer central CLI metadata so command definitions and completions do not drift apart.

---

# 14. Build strategy

Two binaries:

```text
devcontainer-host
host-command
```

## Host daemon

Target:

```text
darwin/arm64
```

Build/install via:

```sh
./host/install-host-bridge
```

Suggested destination:

```text
$HOME/.local/bin/devcontainer-host
```

## Container client

Targets:

```text
linux/arm64
linux/amd64
```

Build during Docker image creation.

Do not compile on `start-dev-container`.

---

# 15. macOS LaunchAgent

Install as user LaunchAgent:

```text
dev.til.devcontainer-host
```

Suggested plist:

```text
~/Library/LaunchAgents/dev.til.devcontainer-host.plist
```

Use absolute paths.

The daemon must run in the graphical login session.

---

# 16. Host installer

Provide:

```text
host/install-host-bridge
```

Responsibilities:

1. Verify macOS.
2. Verify Go.
3. Print discovered Go version.
4. Build `devcontainer-host`.
5. Install it.
6. Generate `host-command.fish`.
7. Store completion file at the agreed persistent host location.
8. Install/update LaunchAgent.
9. Bootstrap/restart service.
10. Verify daemon.
11. Perform `ping` where practical.
12. Print diagnostics on failure.

The script must be idempotent.

Re-running it is the explicit mechanism for rebuilding host Go code and refreshing generated completions.

---

# 17. Socket lifecycle

The daemon owns its socket.

Use restrictive permissions, preferably:

```text
0600
```

Handle stale sockets correctly.

---

# 18. Devcontainer launcher integration

Modify `start-dev-container`.

Normal startup must only:

* detect bridge availability;
* configure transport;
* mount the socket when applicable;
* mount the generated Fish completion file;
* start/attach the container.

It must **not**:

* compile Go code;
* run `go generate`;
* rebuild the daemon;
* rebuild the container client;
* regenerate completions unconditionally.

The bridge being unavailable must not prevent startup.

## Completion mount

Conceptually:

```sh
--mount \
  type=bind,source="$HOME/.local/share/devcontainer/host-command.fish",target=<container-completion-path>,readonly
```

Only add the mount if the source file exists.

Determine the proper target based on the current Fish configuration rather than hard-coding it prematurely.

---

# 19. Existing container lifecycle

Existing behavior must continue working:

```text
one detached container
+
sleep infinity
+
repeated attach
```

No additional daemon should be created per Fish/tmux/Neovim attach.

---

# 20. Multiple containers

One host daemon serves all devcontainers.

The daemon must support concurrent requests.

---

# 21. Path handling

Host-visible absolute project paths may initially be passed directly.

Unsupported container-only paths must return an explicit error.

---

# 22. Client CLI behavior

General form:

```sh
host-command <command> [args...]
```

Examples:

```sh
host-command ping

host-command notification \
    "Build finished" \
    "reda-engine"

host-command open https://github.com

host-command completion fish

host-command doctor
```

Exit codes must be stable and documented.

---

# 23. Fish integration

Fish integration consists primarily of the generated completion file.

Verify inside the running container:

```fish
complete -C 'host-command '
```

This should list the available subcommands.

Also verify nested completion:

```fish
complete -C 'host-command completion '
```

Expected result:

```text
fish
```

Verify static `activate` targets complete appropriately.

The completion file should become available to a newly started Fish shell without rebuilding the container.

Determine whether an already-running Fish process observes an updated completion file automatically. If Fish caches sourced completion definitions, document whether a new shell or explicit reload is required.

Do not use this as justification to regenerate completions during container startup.

---

# 24. Neovim integration

The CLI is the integration API.

No special Neovim plugin is required.

---

# 25. Testing

## Unit tests

Test:

* protocol;
* validation;
* client errors;
* CLI metadata;
* completion generation.

## Completion tests

Add tests ensuring:

```text
host-command completion fish
```

contains every registered top-level command.

Prefer a test deriving expected commands from the CLI registry itself.

Also validate the generated file syntactically using Fish if available:

```sh
fish -n host-command.fish
```

Integration test:

```fish
complete -C 'host-command '
```

should contain expected commands when the generated file is loaded.

## Build lifecycle tests

Verify that running:

```sh
start-dev-container
```

does not modify timestamps of:

```text
devcontainer-host binary
host-command.fish
```

and does not invoke the Go compiler during ordinary startup.

Where feasible, inspect process/log output to prove that no build occurs.

---

# 26. Diagnostics

Support:

```sh
devcontainer-host --version
host-command --version
host-command --help
host-command doctor
host-command completion fish
```

`doctor` should report:

```text
transport
socket/address
connectivity
protocol version
client version
daemon version
completion availability where practical
```

---

# 27. Configuration

Keep configuration minimal.

Likely environment variables:

```text
DEVCONTAINER_HOST_SOCKET
DEVCONTAINER_HOST_ADDR
```

---

# 28. Logging

Daemon logs should contain:

```text
timestamp
request command
request ID
success/failure
duration
error details
```

Never log clipboard contents.

---

# 29. Documentation

Update `README.md` with:

```text
Go Tooling
Host Command Bridge
Host Installation
Available Commands
Fish Completions
Build Lifecycle
Troubleshooting
Security Model
```

Explicitly document:

```text
Changing host bridge Go source:
    ./host/install-host-bridge

Changing container host-command source:
    rebuild devcontainer image

Changing CLI command definitions:
    ./host/install-host-bridge
    rebuild devcontainer image
```

The last case updates both the generated Fish completions and Linux CLI binary.

---

# 30. Implementation sequence

## Phase 1 — Discovery

Inspect:

* repository;
* Dockerfile;
* startup scripts;
* host Go installation;
* Fish config;
* `fish_complete_path`;
* existing completion mounts;
* Neovim Go tooling;
* OrbStack Unix socket behavior.

Specifically determine:

1. whether Fish completion files need regeneration on each container start;
2. whether Fish reloads changed completion files automatically;
3. the cleanest read-only mount target;
4. whether any current startup mechanism already performs source builds;
5. whether there is any valid reason to compile bridge Go code during startup.

Expected decisions:

```text
completion regeneration on start: no
Go compilation on start:         no
```

Deviate only if discovery finds a concrete technical requirement.

## Phase 2 — Go support

Add Go to the image.

## Phase 3 — CLI model and completion generator

Create shared command metadata and:

```sh
host-command completion fish
```

Add tests before adding many commands.

## Phase 4 — Protocol

Implement protocol.

## Phase 5 — Daemon

Implement host daemon.

## Phase 6 — Client

Implement Linux CLI.

## Phase 7 — Host installer

Build daemon and generate Fish completions.

## Phase 8 — Transport

Verify Unix socket behavior and implement fallback if necessary.

## Phase 9 — Launcher integration

Mount:

```text
host bridge transport
Fish completion file
```

Do not build anything.

## Phase 10 — Remaining commands

Add remaining allowlisted operations.

## Phase 11 — Documentation and lifecycle verification

Verify startup does not accidentally become a build step.

---

# 31. Acceptance criteria

## Go

* Go works inside devcontainer.
* Version based on host discovery.
* arm64 and amd64 supported.
* coherent `gopls` setup.

## Compilation lifecycle

Running:

```sh
start-dev-container
```

must not normally invoke:

```text
go build
go install
go run
go generate
```

Host daemon compilation happens through:

```sh
./host/install-host-bridge
```

Container CLI compilation happens during Docker image build.

## Fish completions

This works:

```sh
host-command completion fish
```

A generated completion file is stored persistently on the host.

`start-dev-container` mounts it read-only into the container.

Inside Fish:

```fish
complete -C 'host-command '
```

returns the registered commands.

Adding a CLI command and rerunning the host installer updates the generated completion file.

Normal startup does not regenerate the file.

Missing completions do not prevent the container from starting.

## Host daemon

* managed through LaunchAgent;
* concurrent;
* no arbitrary shell execution;
* stale socket recovery.

## Client

These work:

```sh
host-command ping
host-command notification "Devcontainer" "Hello from Linux"
host-command open https://github.com
host-command clipboard-get
host-command completion fish
host-command doctor
```

## Existing workflow

Existing launcher modes continue working.

---

# 32. Required implementation report

When complete, report:

1. host Go setup discovered;
2. Go version selected;
3. `gopls` strategy;
4. OrbStack Unix-socket test result;
5. final transport;
6. Fish completion search path discovered;
7. chosen completion mount path;
8. whether Fish notices completion-file changes automatically;
9. how completion generation is triggered;
10. confirmation that completion generation does not run on normal startup;
11. host daemon compilation trigger;
12. container client compilation trigger;
13. confirmation that `start-dev-container` performs no normal Go compilation;
14. files added;
15. files modified;
16. commands implemented;
17. tests/results;
18. design deviations;
19. remaining limitations.
