# Devcontainer Host Command Bridge

## Status

Design specification for implementation and learning project.

Primary environment:

```text
Host:         macOS arm64
Runtime:      OrbStack / Docker-compatible containers
Container:    Linux, Debian trixie based
Shell:        Fish
Terminal:     Kitty
Multiplexer:  tmux
Editor:       Neovim
```

Implementation language:

```text
Rust
```

The implementation should favor clear, idiomatic Rust over minimizing LOC. This is also intended as a Rust learning project, so avoid hiding important concepts behind excessive frameworks.

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

The host executes the corresponding macOS operation in the user's graphical login session.

The mechanism must be usable from:

* Fish
* tmux
* Neovim
* build scripts
* shell scripts
* coding agents
* arbitrary programs inside the devcontainer

It must **not** expose unrestricted host shell execution.

Fish completions for `host-command` must be generated from the actual CLI definition and made available automatically inside the container.

---

# 2. Learning goals

Because this is also a Rust learning project, the implementation should provide practical experience with:

* Cargo workspaces
* crates/modules
* ownership and borrowing
* enums and pattern matching
* traits where naturally useful
* `Result` and structured error handling
* serialization with `serde`
* networking
* Unix-domain sockets
* TCP fallback
* concurrency
* process creation
* platform-specific code
* integration tests
* CLI construction
* shell completion generation
* cross-compilation concerns
* macOS `launchd`
* Docker/OrbStack host/container boundaries

Do not deliberately introduce complicated Rust merely to exercise language features.

Prefer the simplest idiomatic implementation that exposes the underlying concepts clearly.

---

# 3. Non-goals

Do not implement:

```text
host-command exec <arbitrary shell command>
```

Do not expose arbitrary:

```text
/bin/sh
/bin/bash
/bin/zsh
osascript source
```

to container clients.

Do not rely on:

```text
docker --privileged
```

for host execution.

Do not mount the macOS root filesystem or complete `$HOME` merely to support host commands.

Do not expose the bridge publicly.

Do not compile Rust code on every `start-dev-container`.

Do not regenerate Fish completions on every `start-dev-container` unless discovery identifies a concrete requirement.

---

# 4. Architecture

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
│ generated Fish completion                          │
│ ~/.local/share/devcontainer/host-command.fish       │
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
│                                                     │
│ Fish / tmux / Neovim / scripts                     │
└─────────────────────────────────────────────────────┘
```

There are two executables:

```text
devcontainer-host
host-command
```

Shared functionality should live in a library crate.

---

# 5. Suggested Rust workspace

Prefer a Cargo workspace:

```text
devcontainer/
├── Cargo.toml
├── Cargo.lock
├── rust-toolchain.toml
│
├── crates/
│   ├── host-command/
│   │   └── src/
│   │       └── main.rs
│   │
│   ├── devcontainer-host/
│   │   └── src/
│   │       └── main.rs
│   │
│   └── host-bridge/
│       └── src/
│           ├── lib.rs
│           ├── protocol.rs
│           ├── client.rs
│           ├── command.rs
│           └── error.rs
│
├── host/
│   ├── dev.til.devcontainer-host.plist
│   └── install-host-bridge
│
├── Dockerfile
├── start-dev-container
└── README.md
```

The names may change if a cleaner workspace layout emerges.

Do not split functionality into crates merely for architectural aesthetics. Three crates are sufficient initially:

* shared library;
* client;
* daemon.

---

# 6. Suggested Rust ecosystem

Evaluate these crates rather than treating them as mandatory:

```text
clap
clap_complete
serde
serde_json
thiserror
uuid
```

Possibly:

```text
tokio
tracing
tracing-subscriber
```

## CLI

Prefer:

```text
clap
```

using derive-based command definitions.

This allows the same CLI definition to drive:

* argument parsing;
* `--help`;
* subcommands;
* validation;
* Fish completion generation.

## Completions

Prefer:

```text
clap_complete
```

This avoids maintaining command definitions twice.

## Serialization

Use:

```text
serde
serde_json
```

## Errors

Use standard Rust errors where sufficient.

`thiserror` is reasonable for structured internal errors.

Avoid introducing `anyhow` everywhere without understanding where typed versus contextual errors are useful.

Using `anyhow` at executable boundaries is acceptable if it improves diagnostics.

---

# 7. Sync versus async

Do not assume Tokio is required.

Before implementation, evaluate whether the daemon actually benefits from async I/O.

The workload is:

```text
accept connection
read small request
execute host operation
write small response
close
```

A straightforward blocking server with one thread per connection may be entirely sufficient and easier to understand.

Possible initial implementation:

```rust
for stream in listener.incoming() {
    let stream = stream?;

    std::thread::spawn(move || {
        handle_connection(stream);
    });
}
```

This would expose useful Rust concepts without introducing the additional complexity of async Rust immediately.

If concurrency or cancellation requirements justify Tokio later, migrate deliberately.

For a first Rust project, synchronous networking is the preferred starting point unless testing demonstrates a concrete limitation.

---

# 8. Transport

## Preferred transport

Use a Unix-domain socket if OrbStack correctly supports exposing a macOS socket to the Linux container.

Host:

```text
$HOME/.local/run/devcontainer-host.sock
```

Container:

```text
/run/devcontainer-host.sock
```

Environment:

```text
DEVCONTAINER_HOST_SOCKET=/run/devcontainer-host.sock
```

Rust API:

```rust
std::os::unix::net::UnixListener
std::os::unix::net::UnixStream
```

This is preferable initially to wrapping socket access through another library.

---

# 9. Mandatory OrbStack experiment

Before implementing the complete RPC layer:

1. Create a Unix listener on macOS.
2. Bind-mount the socket into an OrbStack container.
3. Connect from Linux.
4. Send data in both directions.
5. Test repeated connections.
6. Restart the daemon.
7. Verify stale socket behavior.
8. Restart the container.
9. Document the result.

This experiment should be implemented separately from the complete bridge.

The point is to learn what OrbStack actually does rather than designing around assumptions.

---

# 10. TCP fallback

If Unix-domain socket forwarding is unreliable:

```text
container
    │
    ▼
host.docker.internal:<port>
    │
    ▼
devcontainer-host
```

Suggested port:

```text
45831
```

Possible environment variable:

```text
DEVCONTAINER_HOST_ADDR
```

The application-level protocol must remain independent of Unix versus TCP transport.

Do not prematurely create an elaborate transport abstraction.

A small enum is sufficient:

```rust
enum Transport {
    Unix(PathBuf),
    Tcp(SocketAddr),
}
```

if needed.

---

# 11. Security model

The container is trusted to request a finite set of host capabilities.

It is **not** trusted with arbitrary execution as the macOS user.

This matters because the container may contain:

* project code
* build dependencies
* editor plugins
* language servers
* third-party tools
* coding agents
* downloaded packages

Host operations therefore use an explicit allowlist.

Each operation must:

1. have a fixed protocol command;
2. use a typed request;
3. validate arguments;
4. map to one specific capability;
5. invoke executables directly;
6. never pass untrusted input through a shell.

Use:

```rust
std::process::Command
```

Example:

```rust
Command::new("/usr/bin/open")
    .arg(target)
    .status()?;
```

Never:

```rust
Command::new("sh")
    .arg("-c")
    .arg(user_controlled_string);
```

---

# 12. Initial commands

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

---

# 13. `ping`

```sh
host-command ping
```

Expected:

```text
pong
```

Use this for connectivity and protocol testing.

---

# 14. `notification`

```sh
host-command notification <title> <message>
```

Example:

```sh
host-command notification \
    "CTest" \
    "All tests passed"
```

The host may use:

```text
osascript
```

but user input must not simply be interpolated into AppleScript source.

Prefer passing values as arguments to a fixed script.

---

# 15. `open`

```sh
host-command open <target>
```

Examples:

```sh
host-command open https://github.com
host-command open /Users/til/projects/foo/report.html
```

Use `/usr/bin/open` directly.

---

# 16. `reveal`

```sh
host-command reveal <path>
```

Equivalent host operation:

```text
open -R <path>
```

---

# 17. Clipboard

Set:

```sh
printf '%s' 'hello' | host-command clipboard-set
```

Use stdin rather than a positional argument.

Host may execute:

```text
pbcopy
```

Get:

```sh
host-command clipboard-get
```

Host may execute:

```text
pbpaste
```

Data must be passed verbatim.

Do not log clipboard contents.

---

# 18. `activate`

```sh
host-command activate kitty
```

Use a fixed allowlist of known applications.

Do not allow arbitrary AppleScript source.

Example server representation:

```rust
enum Application {
    Kitty,
    Finder,
}
```

Map those variants to explicitly known host behavior.

---

# 19. Arbitrary AppleScript

Do not expose:

```text
host-command osascript <source>
```

If another automation becomes useful, add another typed operation.

For example:

```text
activate
notification
reveal
open
```

rather than turning AppleScript into a generic escape hatch.

---

# 20. Protocol

Use versioned NDJSON.

Example request:

```json
{
  "version": 1,
  "id": "e65bf389-fc09-429b-b05d-d21530bf4489",
  "command": "notification",
  "args": {
    "title": "Build",
    "message": "Finished"
  }
}
```

Prefer strongly typed Rust representations.

For example:

```rust
#[derive(Debug, Serialize, Deserialize)]
struct Request {
    version: u32,
    id: Uuid,
    command: Command,
}
```

with:

```rust
#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "name", content = "args")]
enum Command {
    Ping,
    Notification {
        title: String,
        message: String,
    },
    Open {
        target: String,
    },
    // ...
}
```

The exact JSON representation may differ if a cleaner serde representation emerges.

Prefer using Rust enums instead of dispatching on arbitrary string maps.

---

# 21. Response types

Successful response:

```json
{
  "version": 1,
  "id": "...",
  "ok": true,
  "result": {}
}
```

Error:

```json
{
  "version": 1,
  "id": "...",
  "ok": false,
  "error": {
    "code": "invalid_argument",
    "message": "title must not be empty"
  }
}
```

Stable error categories:

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

Represent these as a Rust enum where practical.

---

# 22. Protocol framing

Initially:

```text
one connection
one JSON line request
one JSON line response
connection closes
```

Do not add:

* connection pooling;
* multiplexing;
* streaming RPC;
* custom binary framing.

Those solve problems this project does not currently have. `\s`

---

# 23. Limits

Suggested:

```text
request limit:       1 MiB
read timeout:        5 seconds
host command timeout: 10 seconds
clipboard limit:     10 MiB
```

Investigate how cleanly these can be implemented with synchronous standard-library sockets.

Do not introduce async solely for timeout support without first evaluating simpler approaches.

---

# 24. Rust host setup — mandatory discovery

Rust is not currently assumed to be installed or configured.

Before changing the container, inspect the macOS host.

Run:

```sh
command -v rustc
command -v cargo
command -v rustup

rustc --version
cargo --version
rustup --version
rustup show
```

Check installation paths:

```sh
type -a rustc
type -a cargo
type -a rustup

echo "$PATH"
```

Check package managers:

```sh
brew list --versions rust 2>/dev/null
brew list --versions rustup 2>/dev/null

mise current 2>/dev/null
mise ls rust 2>/dev/null

asdf current rust 2>/dev/null
```

Inspect Fish configuration:

```sh
rg -n \
    'cargo|rustup|rustc|RUSTUP_HOME|CARGO_HOME|mise|asdf' \
    ~/.config/fish \
    ~/.config 2>/dev/null
```

Inspect:

```sh
echo "$CARGO_HOME"
echo "$RUSTUP_HOME"
```

and:

```sh
rustup toolchain list
rustup target list --installed
rustup component list --installed
```

Record what is discovered.

---

# 25. Rust toolchain management

Prefer using:

```text
rustup
```

for this repository.

Add:

```text
rust-toolchain.toml
```

Example structure:

```toml
[toolchain]
channel = "stable"
components = [
    "rustfmt",
    "clippy",
]
```

Consider pinning an exact Rust version later if reproducibility requires it.

For a learning project, using current stable through the repository's toolchain file is reasonable.

Do not rely implicitly on whatever Rust version Debian happens to package.

---

# 26. Container Rust installation

Add a real Rust toolchain to the devcontainer.

Requirements:

```text
cargo
rustc
rustfmt
clippy
```

The installation must:

* work as the development user;
* support Linux arm64;
* support Linux amd64;
* respect `rust-toolchain.toml`;
* not use host binaries;
* not share platform-specific build outputs with macOS.

Do not mount host:

```text
~/.cargo
~/.rustup
target/
```

directly into Linux merely to save installation time.

Host and container artifacts are for different platforms.

---

# 27. rust-analyzer

Inspect the existing Neovim/LazyVim LSP setup first.

Determine whether `rust-analyzer` is provided through:

* Mason;
* rustup;
* the container image;
* another mechanism.

Prefer one authoritative installation.

If installed through rustup:

```sh
rustup component add rust-analyzer
```

If the Neovim setup already expects Mason to manage it, avoid installing another competing binary.

Document the resulting strategy.

---

# 28. Useful development tools

Evaluate installing:

```text
cargo-edit
cargo-nextest
cargo-watch
```

but they are not required for initial implementation.

Do not preload a large collection of Rust utilities just because they exist.

Required tools are:

```text
cargo
rustc
rustfmt
clippy
rust-analyzer strategy
```

---

# 29. Build lifecycle

Normal:

```text
start-dev-container
```

must not invoke:

```text
cargo build
cargo install
cargo run
```

for the bridge.

Startup should remain container startup, not become a build system. `\s`

---

# 30. Host daemon compilation

The host daemon is compiled by:

```sh
./host/install-host-bridge
```

Example conceptual build:

```sh
cargo build \
    --release \
    --package devcontainer-host
```

Install:

```text
target/release/devcontainer-host
    ->
~/.local/bin/devcontainer-host
```

The exact target directory may differ if the workspace is configured differently.

The installer owns:

* building host daemon;
* installing it;
* generating completions;
* updating LaunchAgent;
* restarting daemon.

Re-running it must be safe.

---

# 31. Linux client compilation

The `host-command` Linux binary belongs in the container image.

It should be compiled during Docker image construction.

Two viable approaches should be evaluated:

## Option A — Rust installed first

Install Rust into the dev image and:

```sh
cargo build --release --package host-command
```

during image construction.

## Option B — multi-stage build

Use a Rust builder stage and copy the resulting client binary into the final development image.

Because Rust is desired in the development container anyway, Option A may be simpler.

Choose based on the existing Dockerfile architecture.

---

# 32. Build caching

Because Rust compilation can be significantly more expensive than Go compilation, investigate Docker layer structure carefully.

Keep dependency resolution/build caching effective.

Consider structuring Dockerfile layers so source changes do not unnecessarily invalidate the complete Rust toolchain installation.

Do not introduce cargo-chef initially unless ordinary Docker caching proves inadequate.

This project should teach Cargo before teaching an additional Cargo build-planning tool. `\s`

---

# 33. Fish completion generation

The CLI must support:

```sh
host-command completion fish
```

Use the actual `clap::Command` definition to generate completions through `clap_complete`.

Do not manually maintain command names in a Fish script.

Conceptually:

```rust
clap_complete::generate(
    clap_complete::Shell::Fish,
    &mut command,
    "host-command",
    &mut std::io::stdout(),
);
```

The exact API should follow the installed crate version.

---

# 34. Completion lifecycle

Suggested persistent host file:

```text
$HOME/.local/share/devcontainer/host-command.fish
```

The host installation step generates it.

Normal `start-dev-container` only mounts it.

Expected lifecycle:

```text
./host/install-host-bridge
    │
    ├── cargo build devcontainer-host
    │
    └── generate host-command.fish
                    │
                    ▼
~/.local/share/devcontainer/host-command.fish
                    │
                    │ read-only bind mount
                    ▼
            devcontainer Fish
```

No unconditional completion generation at startup.

---

# 35. How to generate host completions

Because the container client binary targets Linux, do not assume it can run on macOS.

Possible implementations:

### Preferred

The `host-command` crate should also build natively on macOS because the CLI parsing/completion logic itself is platform-independent.

The installer may therefore execute:

```sh
cargo run \
    --quiet \
    --package host-command \
    -- completion fish
```

to generate completions.

The actual host RPC invocation path need not be used.

### Alternative

Move CLI definition into the shared library and create a small generation utility.

Prefer the first approach if the client already compiles cleanly on Darwin.

Avoid inventing a separate code generator unnecessarily.

---

# 36. Completion mount

Inspect the current Fish configuration and:

```fish
$fish_complete_path
```

before selecting the target.

Possible target:

```text
~/.config/fish/completions/host-command.fish
```

But do not overwrite or conflict with existing mounted dotfiles.

A dedicated mounted path is acceptable if Fish is configured to search it.

The file should be mounted read-only.

---

# 37. Completion refresh behavior

Explicitly investigate:

1. whether Fish reads newly mounted completion files automatically;
2. whether an existing Fish process caches an already-loaded completion definition;
3. whether a new shell is required after regenerating the file.

Regardless of the answer, `start-dev-container` should not normally regenerate the file.

Document any necessary reload behavior.

---

# 38. macOS LaunchAgent

Suggested label:

```text
dev.til.devcontainer-host
```

Suggested path:

```text
~/Library/LaunchAgents/dev.til.devcontainer-host.plist
```

Executable:

```text
~/.local/bin/devcontainer-host
```

Use absolute paths.

The daemon must run in the logged-in graphical user session.

That is important for:

```text
osascript
notifications
application activation
clipboard interaction
```

---

# 39. Installer

Provide:

```text
host/install-host-bridge
```

Responsibilities:

1. verify macOS;
2. verify Rust toolchain;
3. show Rust version;
4. build `devcontainer-host --release`;
5. install binary;
6. generate Fish completion;
7. install/update LaunchAgent;
8. bootstrap/restart daemon;
9. verify daemon health;
10. provide useful diagnostics.

Must be idempotent.

---

# 40. Socket lifecycle

The daemon owns the socket.

On startup:

1. create parent directory;
2. detect stale socket;
3. avoid deleting a socket owned by an active server;
4. remove genuinely stale socket;
5. bind;
6. set restrictive permissions;
7. listen.

Target permissions:

```text
0600
```

Research the most idiomatic Rust/Unix approach for setting socket permissions after binding.

---

# 41. Graceful shutdown

Handle at least:

```text
SIGTERM
SIGINT
```

where practical.

The daemon should remove its socket when shutting down gracefully.

For the first implementation, evaluate whether adding a signal-handling crate is justified.

`ctrlc` or Tokio signal handling may be reasonable, but understand the lifecycle before selecting one.

---

# 42. Container launcher integration

Modify:

```text
start-dev-container
```

Normal startup should:

* detect bridge availability;
* configure transport;
* mount Unix socket if applicable;
* mount Fish completion file;
* pass required environment variables;
* start or attach to container.

It must not:

* build Rust;
* run Cargo;
* install dependencies;
* regenerate completions;
* restart the host daemon automatically.

If the bridge is unavailable, container startup still succeeds.

---

# 43. Multiple containers

One macOS daemon serves all devcontainers.

The daemon must safely handle concurrent connections.

Do not create one daemon per:

* shell;
* tmux instance;
* Neovim instance;
* project;
* container.

---

# 44. Path handling

Your development setup generally keeps project paths compatible between macOS and the container.

For v1, allow host-visible absolute paths.

Reject obvious container-only paths cleanly.

Do not build a complex path-translation subsystem initially.

---

# 45. Client CLI behavior

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

host-command reveal \
    "$PWD/cmake-build-debug/core.12345"

printf 'foo\nbar\n' |
    host-command clipboard-set

host-command clipboard-get

host-command completion fish

host-command doctor
```

The program must be suitable for scripts.

Use:

```text
stdout = command result
stderr = diagnostics/errors
```

---

# 46. Exit codes

Define stable semantics.

Suggested:

```text
0  success
1  host operation failed
2  CLI/usage error
3  connection error
4  protocol error
```

`clap` may already use specific exit behavior for parsing failures; inspect that behavior before inventing conflicting codes.

Document the final contract.

---

# 47. `doctor`

Implement:

```sh
host-command doctor
```

Useful output:

```text
transport: unix
socket: /run/devcontainer-host.sock
connection: ok
protocol: 1
client: 0.1.0
daemon: 0.1.0
```

The command should help diagnose:

* missing socket mount;
* daemon not running;
* incompatible protocol;
* client/daemon version mismatch.

---

# 48. Version information

Both executables:

```sh
host-command --version
devcontainer-host --version
```

Version should derive from Cargo package metadata.

Avoid manually duplicating version numbers.

---

# 49. Logging

Evaluate:

```text
tracing
tracing-subscriber
```

for daemon logging.

A simpler standard logging approach is also acceptable initially.

Log:

```text
timestamp
command
request ID
status
duration
error
```

Do not log:

```text
clipboard contents
full arbitrary request bodies
sensitive payloads
```

---

# 50. Testing strategy

## Unit tests

Test:

* protocol serialization;
* deserialization;
* command enums;
* invalid data;
* unsupported protocol version;
* validation;
* error mapping;
* CLI definitions.

## Completion tests

Verify:

```sh
host-command completion fish
```

contains all registered commands.

Validate syntax:

```sh
fish -n host-command.fish
```

where Fish is available.

Verify actual completion behavior:

```fish
complete -C 'host-command '
```

---

# 51. Integration tests

Create tests that:

1. start temporary server;
2. connect client;
3. send `ping`;
4. validate response;
5. send malformed request;
6. test error handling;
7. test simultaneous connections.

Use temporary Unix sockets.

Avoid invoking real:

```text
Finder
notifications
clipboard
```

in ordinary automated tests.

---

# 52. Host command abstraction

Keep host command execution testable.

For example, a trait may be appropriate:

```rust
trait HostOperations {
    fn notification(&self, title: &str, message: &str)
        -> Result<(), HostError>;

    fn open(&self, target: &str)
        -> Result<(), HostError>;
}
```

A production implementation invokes macOS programs.

A test implementation records requests.

This is a good place to learn traits because there is an actual abstraction boundary.

Do not create traits for everything else merely because Rust has traits. `\s`

---

# 53. Platform-specific code

The daemon is macOS-specific.

Use conditional compilation where useful:

```rust
#[cfg(target_os = "macos")]
```

The client should compile on:

```text
Linux
macOS
```

even if host command transport is primarily used from Linux.

Keeping the CLI compilable on macOS also simplifies completion generation.

---

# 54. Formatting and linting

The repository must support:

```sh
cargo fmt --check
cargo clippy --all-targets --all-features
cargo test
```

Treat Clippy warnings seriously, but do not blindly follow every lint without understanding it.

Prefer learning why a lint exists over adding:

```rust
#[allow(...)]
```

immediately.

---

# 55. README additions

Add:

```text
Rust Toolchain
Architecture
Host Command Bridge
Host Installation
Available Commands
Fish Completions
Building
Testing
Troubleshooting
Security Model
```

Document:

```text
Host source changed:
    ./host/install-host-bridge

Container client source changed:
    rebuild devcontainer image

CLI changed:
    ./host/install-host-bridge
    rebuild devcontainer image
```

---

# 56. Implementation sequence

## Phase 1 — Rust basics and discovery

Before implementing the bridge:

* inspect host Rust environment;
* install/configure rustup if needed;
* add `rust-toolchain.toml`;
* add Cargo workspace;
* confirm `cargo fmt`;
* confirm `cargo clippy`;
* confirm `cargo test`.

Create a tiny test executable if necessary.

The goal is to understand the basic Cargo workflow before implementing networking.

---

## Phase 2 — Rust in the devcontainer

Add Rust tooling.

Verify inside the container:

```sh
rustc --version
cargo --version
cargo fmt --version
cargo clippy --version
```

Verify Neovim `rust-analyzer`.

---

## Phase 3 — OrbStack Unix socket experiment

Write a tiny Rust Unix socket server/client.

Do not use the final protocol.

Verify host-to-container socket behavior independently.

This is a useful first practical Rust networking exercise.

---

## Phase 4 — CLI

Implement `host-command` using `clap`.

Initially:

```text
ping
completion fish
```

Generate Fish completions.

---

## Phase 5 — Protocol

Implement typed `serde` request/response structures.

Write serialization tests.

---

## Phase 6 — Server

Implement synchronous daemon.

Initially support only:

```text
ping
```

Get the complete round trip working.

---

## Phase 7 — Host installer and LaunchAgent

Install the Rust daemon and make it survive login/restarts.

---

## Phase 8 — Container integration

Mount the transport and completions.

Verify:

```sh
host-command ping
```

inside the normal development environment.

---

## Phase 9 — Host capabilities

Add commands one at a time:

```text
notification
open
reveal
clipboard-set
clipboard-get
activate
```

Test each separately.

---

## Phase 10 — Diagnostics

Add:

```text
doctor
versions
structured errors
logging
```

---

## Phase 11 — Hardening

Review:

* input validation;
* shell injection;
* stale sockets;
* timeouts;
* concurrent requests;
* malformed JSON;
* oversized requests;
* daemon failure;
* incompatible versions.

---

# 57. Things deliberately deferred

Do not initially implement:

* async Rust solely for fashion;
* custom binary RPC;
* HTTP;
* gRPC;
* TLS;
* authentication tokens for Unix-socket mode;
* plugin architecture;
* runtime command registration;
* arbitrary host execution;
* complex path translation;
* connection pools;
* dynamic configuration reload;
* cargo-chef;
* elaborate installer frameworks.

Each may be revisited if the project produces an actual requirement.

---

# 58. Acceptance criteria

## Rust environment

Inside devcontainer:

```sh
cargo --version
rustc --version
cargo fmt --version
cargo clippy --version
```

work.

`rust-analyzer` works in Neovim.

The repository contains a Rust toolchain declaration.

---

## Build lifecycle

Normal:

```sh
start-dev-container
```

does not invoke Cargo.

Host daemon is rebuilt through:

```sh
./host/install-host-bridge
```

Linux client is rebuilt as part of the devcontainer image.

---

## Transport

The result of the OrbStack Unix-socket experiment is documented.

Unix sockets are used if reliable.

TCP fallback is implemented if necessary.

---

## Client

Inside the container:

```sh
host-command ping
```

returns:

```text
pong
```

These work:

```sh
host-command notification \
    "Devcontainer" \
    "Hello from Linux"

host-command open https://github.com

printf 'hello' | host-command clipboard-set

host-command clipboard-get

host-command doctor
```

---

## Fish completions

This works:

```sh
host-command completion fish
```

Generated completions come from the actual Rust CLI definition.

The completion file is generated during host installation and mounted read-only.

Normal container startup does not regenerate it.

Inside Fish:

```fish
complete -C 'host-command '
```

lists the available subcommands.

---

## Security

No supported protocol request allows direct execution of:

```text
arbitrary shell
arbitrary executable
arbitrary AppleScript
```

Every host capability has an explicitly implemented typed operation.

---

## Existing workflow

Existing `start-dev-container` and attach behavior remains unchanged when the bridge is unavailable.

Bridge failure never prevents normal development-container startup.

---

# 59. Suggested first milestones

For learning purposes, resist implementing the entire document at once.

A sensible progression is:

```text
Milestone 1
Rust workspace builds
    ↓
Milestone 2
Rust Unix socket hello-world
Mac -> OrbStack container
    ↓
Milestone 3
host-command ping
    ↓
Milestone 4
LaunchAgent
    ↓
Milestone 5
notification
    ↓
Milestone 6
clap-generated Fish completions
    ↓
Milestone 7
remaining commands
    ↓
Milestone 8
hardening
```

Each milestone should leave something runnable.

---

# 60. Required implementation notes

As work progresses, record:

1. existing host Rust setup;
2. chosen Rust installation strategy;
3. selected Rust toolchain;
4. `rust-analyzer` strategy;
5. OrbStack Unix socket experiment and result;
6. sync versus async decision and reasoning;
7. final transport;
8. Fish completion path;
9. Fish reload behavior;
10. host build lifecycle;
11. container client build lifecycle;
12. relevant Rust concepts learned or encountered;
13. security decisions;
14. implementation deviations;
15. remaining limitations.

The document is a design guide, not a requirement to preserve an early architectural decision when experimentation proves it wrong. In particular, the Unix-socket experiment should be allowed to influence the final transport design.
