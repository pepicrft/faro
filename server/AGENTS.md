# Faro server

This is an independent Once workspace with a Phoenix/Bandit JSON service. It is
not an implemented agent backend. It has no accounts, database, model providers,
background jobs, or native-client integration yet. Keep public routes limited to
health and scaffold status until authentication and authorization are designed.

## Development

From the repository root:

```sh
mise -C server install github:tuist/once erlang elixir helm
mise -C server run setup
mise run check:server
mise run build:server
mise run dev:server
mise run release:server
mise -C server run smoke
mise run check:helm
```

Once owns compilation, tests, linting, and release assembly. Fetch dependencies
with `mix deps.get --check-locked` before invoking Once directly; the mise tasks
handle that. Commit `mix.lock` and `mise.lock`. Use `mix deps.get` without
`--check-locked` only when deliberately updating dependencies.

`once.toml` uses explicit targets because Once 0.68.2's native Mix discovery
emits an unmatched optional Rebar script source during validation. Keep this
workaround here, not in a fork or modification of the Once installation.

Every ExUnit module must use `async: true`. Never change application environment
or other global state in a test. Test through explicit dependencies and the real
endpoint. Treat liveness and readiness separately when adding external services.

Production reads `FARO_SECRET_KEY_BASE` at runtime and requires at least 64 bytes.
Never copy development/test keys into production, images, chart values, or tests
of production deployment. Do not log credentials or future agent message content.
Keep migrations, persistence, auth, provider integration, and event protocols out
of the welcome/status scaffold until they are actually implemented.

## Delivery

`Dockerfile` builds the release through Once and ships only the release and
runtime system libraries, running as an unprivileged user. Its Once checksums
must stay aligned with the root toolchain pin when updating Once.

`../deploy/helm/faro` defines an internal-only service. Production values target
the Pepicrft workload cluster managed in the sibling `../../indie` repository. `../deploy/indie` is a staged
handoff, not an active cluster registration. Do not apply it or unsuspend the
HelmRelease without an explicit deployment request and prerequisite provisioning.
No database, public domain, TLS termination, or analytics events are configured.
Only add safe named analytics events after meaningful product outcomes exist;
never include personal-agent content or credentials.
