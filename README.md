# Faro

An open-source personal agent with a shared Rust core and native interfaces.

This is the initial application and build scaffold, modeled after
[`atlas-native` in tuist/tuist](https://github.com/tuist/tuist/tree/main/atlas-native).
Every client displays metadata loaded from the same Rust core. There is no model
provider, conversation runtime, or tool execution yet. A separate Phoenix server
provides health/status endpoints and a PostgreSQL foundation; native clients are
not connected to it yet.

## Stack

| Layer | Implementation |
| --- | --- |
| Shared core and CLI | Rust |
| Server | Elixir, Phoenix, and Bandit |
| macOS, iPhone, and iPad | SwiftUI |
| Android | Kotlin with native Android widgets, like Atlas |
| Linux and Windows desktop | GPUI |
| Product builds and tests | [Once](https://github.com/tuist/once) |
| Toolchain management | [mise](https://mise.jdx.dev) |

Swift imports an authored C header/module map; Kotlin loads the Rust shared
library through JNI. The CLI and GPUI client consume Rust directly. Native
adapters are deliberately small. Future agent behavior belongs in the core;
OS integrations, permissions, presentation, and credential storage belong in
platform adapters.

## Get started

Install mise, then run from the repository root:

```sh
mise install
mise exec -- once auth login --provider tuist
mise run check
mise run build:cli
.once/out/FaroCLI/faro
.once/out/FaroCLI/faro --help
```

`mise.toml` pins Once 0.68.2, Rust 1.96.0, Java 21.0.2, and Kotlin 2.4.10.
Xcode supplies Swift and the Apple SDKs. Android SDK command-line tools and
platform packages must be installed separately, as described below.

Once owns the explicit graph in `once.toml` and `desktop/once.toml`. There are no
Gradle, SwiftPM, or generated Xcode projects. `Cargo.toml` and `Cargo.lock` remain
authoritative for Rust dependencies and support editors, formatting, and Clippy.
Cargo's default members are the lightweight core and CLI, so checking them does
not compile GPUI.

Like Atlas, the pinned Once release needs third-party sources materialized before
resolving the per-crate graph. Build/check/test tasks run `prepare:rust` first,
which vendors locked dependencies into ignored `.once/vendor`. The initial
preparation downloads GPUI's dependency tree even when building only the CLI;
subsequent compilation is limited to the selected target's dependencies.
If invoking Once directly, prepare first:

```sh
mise run prepare:rust
mise exec -- once query targets
mise exec -- once query validate-workspace
mise exec -- once build FaroCLI
mise exec -- once build FaroCLI  # Unchanged compilation actions should hit the cache.
```

Both Once workspaces use the shared cache and build/test insights in
[**pedrotuist/faro**](https://tuist.dev/pedrotuist/faro). Sign in once with the
command above; the native and server workspaces reuse the same local session.
Once prints a live Tuist run link during builds and tests.

For offline work or contributing without project access, keep everything local:

```sh
ONCE_CACHE_PROVIDER=local mise run check
ONCE_CACHE_PROVIDER=local mise run check:server
```

GitHub Actions uses short-lived OpenID Connect credentials, not a stored Tuist
token. Enable the repository variable `TUIST_CI_ENABLED=true` after installing the
Tuist GitHub App and linking this project to `pepicrft/faro`. Native jobs and server
checks then authenticate automatically. Fork pull requests and Dependabot runs
always stay local. Leaving the variable unset also keeps CI local, allowing a safe
initial rollout or temporary opt-out without changing the build graph.

The isolated multi-architecture Docker build deliberately uses local Once caching
and BuildKit layer caching, without copying Tuist credentials into images or build
layers. Server compilation, tests, and release assembly already report to Tuist
from the preceding CI check job.

## Elixir server

`server/` is an independent Once workspace, so native development does not require
Elixir or Erlang. Its toolchain matches Gesttalt: Elixir 1.20.1 and Erlang 29.0.2.
Install the server tools and Hex/Rebar, then use the root convenience tasks:

```sh
mise -C server install github:tuist/once erlang elixir helm
mise -C server run setup
mise run check:server
mise run build:server
mise run dev:server
```

The local server listens on `127.0.0.1:4000`. It exposes `/health/live`,
`/health/ready`, and `/api/v1/status`, which explicitly reports that the agent
runtime is not configured. Production uses PostgreSQL; local development enables
it only with `FARO_DATABASE_ENABLED=true` and `FARO_DATABASE_URL`. There are no
application tables, accounts, model connections, or native-client transport yet.

`mise run release:server` assembles a production release under
`server/.once/out/mix_release/release`; `mise -C server run smoke` relocates it,
starts it with an ephemeral key, and probes the real HTTP routes. Production
requires a runtime `FARO_SECRET_KEY_BASE` of at least 64 bytes, a database URL,
and its public certificate authority file for verified database TLS.

The server has its own pinned toolchains and explicit Once targets. Its mise
tasks fetch locked dependencies before graph loading. Direct Once commands run
from `server/` after `mix deps.get --check-locked`.

### Server delivery

Like Gesttalt, GitHub Actions builds a Linux amd64/arm64 container and publishes it
on successful main-branch server checks. The Helm chart in `deploy/helm/faro`
targets the Pepicrft workload cluster managed by `../indie`. Production values use
its existing node pool and External Secrets store.

The public endpoint is `https://faro.fyi`, with automatic HTTPS through the
cluster's shared ingress and Certificate Manager.
CloudNativePG provisions a dedicated PostgreSQL instance; the Barman plugin
archives logs and takes daily backups to Hetzner object storage with 30-day
retention. Flux registrations in `pepicrft/indie` track this repository's chart
and automatically commit newly published image digests for deployment. See
[the deployment guide](deploy/README.md) for secrets, bootstrap prerequisites,
and operational checks. Public routes expose only health and service metadata,
not personal-agent functionality.

## Products

| Product | Command | Output |
| --- | --- | --- |
| CLI | `mise run build:cli` | `.once/out/FaroCLI/faro` |
| macOS | `mise run build:macos` | `.once/out/FaroMac/Faro.app` |
| iOS simulator | `mise run build:ios` | `.once/out/FaroIOS/Faro.app` |
| iOS device (compile validation) | `mise run build:ios-device` | `.once/out/FaroIOSDevice/Faro.app` |
| Android | `mise run build:android` | `.once/out/FaroAndroid/FaroAndroid.apk` |
| GPUI desktop | `mise run build:desktop` | `.once/out/desktop/FaroDesktop/faro_desktop` |
| Elixir server release | `mise run release:server` | `server/.once/out/mix_release/release` |

Windows executable paths have an additional `.exe` suffix. Products build on their
native host, not through universal cross-compilation. GPUI can also be built on
macOS for development; the intended macOS product is SwiftUI.

### macOS and iOS

Install Xcode and select it with `xcode-select`. On an Apple Silicon Mac:

```sh
mise run setup:apple
mise run build:macos
open .once/out/FaroMac/Faro.app

mise run build:ios
xcrun simctl install booted .once/out/FaroIOS/Faro.app
xcrun simctl launch booted io.github.pepicrft.faro
```

The iOS commands require a booted arm64 iOS simulator. Minimum versions are
macOS 14 and iOS 17. The iOS app supports iPhone and iPad. The macOS build uses
the host architecture; the iOS targets explicitly use arm64.

`FaroIOSDevice` compiles for a physical device but is only ad-hoc signed: it is
**not installable on an iPhone** without appropriate development/distribution
signing and provisioning. App icons, notarization, store publishing, automatic
updates, and release signing are not configured.

### Android

Install the Android SDK command-line tools and expose `sdkmanager` on `PATH`.
Set `ANDROID_HOME` to your SDK installation, accept its licenses explicitly,
then install the required packages and create a workspace-local debug key:

```sh
export ANDROID_HOME=/path/to/android-sdk
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
sdkmanager --licenses
mise run setup:android
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/27.3.13750724"
mise run build:android

adb install -r .once/out/FaroAndroid/FaroAndroid.apk
adb shell am start -n io.github.pepicrft.faro/.MainActivity
```

The setup task installs SDK 35, build-tools 35.0.0, NDK 27.3.13750724, platform
tools, and the Rust Android target. The APK supports Android 8.0+ and packages
`libfaro_core.so` for **arm64-v8a only**. Use an arm64 device or emulator.
The standard public Android debug-key password is used; the generated keystore
stays in ignored `.once/`. Mise supplies `ANDROID_DEBUG_KEYSTORE` as a local path,
so the key is never copied into a shared-cache build output. Production signing
and Play Store bundles are separate
future work. The setup script requires Bash, including on Windows.

### GPUI desktop

On Ubuntu, install native build dependencies:

```sh
sudo apt-get update
sudo apt-get install -y clang cmake pkg-config libasound2-dev libcap-ng-dev \
  libfontconfig-dev libfreetype-dev libwayland-dev libxkbcommon-x11-dev \
  libx11-xcb-dev libxcb1-dev libx11-dev libssl-dev libvulkan-dev libdbus-1-dev
mise run build:desktop
.once/out/desktop/FaroDesktop/faro_desktop
```

On Windows, install Visual Studio Build Tools with the Desktop development with
C++ workload, a Windows SDK, and LLVM. Run `mise run build:desktop` from a
configured development shell. This produces a desktop executable, not an installer.
The GPUI client currently contains only the welcome screen; it is not a chat
editor or an accessibility-complete product.

The lockfile intentionally keeps `libc` at 0.2.189 and `windows-capture` at 1.3.6
for GPUI 0.2.2's dependencies. Its archive dependency still uses `xattr` 0.2,
which needs the Linux `ENOATTR` alias removed in `libc` 0.2.190. Its capture
dependency expects the five-argument settings constructor from `windows-capture`
1.3.6, not the newer API. Revisit these versions when upgrading GPUI and validate
both Cargo checks and Once builds on Linux and Windows.

## Tests and CI

```sh
mise run check           # Graph validation, formatting, core/CLI Clippy and tests.
mise run test            # Rust core, C/JNI boundaries, and CLI command tests.
mise run test:macos      # Swift adapter tests against the real Rust static library.
mise run test:ios        # The same bridge tests on an iOS simulator.
mise run check:desktop   # GPUI graph, formatting, and Clippy.
```

`.github/workflows/faro.yml` defines Rust checks and CLI builds on Linux, macOS,
and Windows; SwiftUI builds and bridge tests on macOS/iOS; an Android APK build;
and GPUI checks/builds on all three desktop platforms. CI retains build artifacts
for 14 days, without production signing credentials or automatic publication.
Raw executable artifacts may need executable permissions restored after download.

Locally verified on Apple Silicon: all six products build, the eight Rust tests
and four Swift bridge tests pass, desktop Clippy passes, the APK signature verifies,
and unchanged GPUI actions restore from cache. The Linux and Windows jobs are
defined but have not been executed from this host. GPUI currently brings a
future-compatibility warning from its transitive `block` dependency.

The bootstrap bridge exposes read-only UTF-8 metadata: C pointers have process
lifetime and must never be freed, and JNI uses bounded integer/byte calls rather
than Java object ownership. It is intentionally not a future streaming/session
protocol. Tests cover parity across the bridges and invalid field/offset handling.

## License

Faro is available under the [MIT License](LICENSE). Dependencies retain their own
licenses.
