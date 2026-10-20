# Faro

Faro is an open-source personal agent. This repository currently contains native
client scaffolds, shared metadata, and a Phoenix server with health/status routes,
not a working model/tool runtime.

## Architecture

- `core/`: dependency-free Rust domain code and bootstrap C/JNI adapters.
- `cli/`: Rust CLI, consuming the core directly.
- `apple/`: shared SwiftUI macOS/iOS app, a Swift adapter, and real-bridge tests.
- `android/`: Kotlin and Android platform widgets, following Atlas native's setup.
- `desktop/`: Rust/GPUI client for Linux and Windows; also buildable on macOS.
- `server/`: independent Elixir/Phoenix Once workspace; see `server/AGENTS.md`.
- `deploy/`: server Helm chart, production values, and deployment operations guide.
- `once.toml`, `desktop/once.toml`: one explicit native Once workspace. Cargo manifests
  and the committed lockfile support dependency resolution, Clippy, and editors.

## Development

Use `mise install`, then `mise run check`, `mise run test`, and the `build:*`
tasks in `mise.toml`. Once owns product compilation and tests. Do not introduce
Gradle, SwiftPM, or generated Xcode projects to work around Once issues.

Once is pinned to 0.68.2, like the Atlas reference. `prepare:rust` must run before
calling Once directly on a fresh clone; all build/check/test tasks depend on it.
It materializes locked third-party sources in ignored `.once/vendor`. Prepare
serially before builds; do not vendor concurrently into the same directory.

Keep reusable client behavior in Rust and OS presentation, permissions, background
scheduling, and credential storage in native adapters. Server-side lifecycle and
future service integrations belong in Elixir; do not introduce a Rust native
extension into the server just to share bootstrap metadata. Do not add pretend model
responses, embedded credentials, or network integrations to this scaffold.

The bootstrap C strings are immutable process-lifetime pointers: never free them.
JNI currently uses only integers and opaque VM pointers, not dynamic Java objects.
Use an established JNI library and a versioned boundary for future session APIs.
Keep package names and JNI exported symbols in sync and test boundary inputs.

## Validation

- `mise run check`: graph validation, Rust formatting, core/CLI Clippy and tests.
- `mise run check:desktop`: GPUI graph validation, formatting, and Clippy.
- `mise run test:macos` / `mise run test:ios`: real Swift-to-Rust bridge tests.
- `mise run build:cli|macos|ios|ios-device|android|desktop`: individual products.

Android is arm64-v8a, API 26+, with SDK 35/build-tools 35.0.0/NDK 27.3.13750724.
iOS targets Apple Silicon simulators and arm64 devices; macOS requires 14+.
Device bundles are ad-hoc signed for compile validation, not installable previews.
Never commit or upload keystores, provisioning profiles, or private signing keys.
Both Once workspaces share Tuist project `pedrotuist/faro` for caching and build/test
insights. Authenticate with `mise exec -- once auth login --provider tuist`.
`ONCE_CACHE_PROVIDER=local` is the offline/contributor escape hatch. CI uses OpenID
Connect only when `TUIST_CI_ENABLED=true`; fork and Dependabot runs remain local.
Do not add long-lived Tuist tokens to the repository or expose signing keys as
cacheable outputs. Android signing must use the local `ANDROID_DEBUG_KEYSTORE`
path rather than the `debug_keystore` target attribute, which copies the key.
Server deployment is separate: it reads runtime secrets from External
Secrets and uses `faro.fyi`, PostgreSQL, and Barman backups on the Pepicrft workload
cluster. Live Flux registrations belong to `pepicrft/indie`; see `deploy/README.md`.
Do not edit infrastructure repositories or apply cluster resources as part of local
validation. Deployment still requires an explicit request.
