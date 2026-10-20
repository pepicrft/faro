# Faro server

This is an independent Once workspace with a Phoenix/Bandit JSON service. It is
not an implemented agent backend. Production has a dedicated PostgreSQL database,
but no application tables, accounts, model providers, background jobs, or native-client
integration yet. Keep public routes limited to health and service metadata until
authentication and authorization are designed.

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

Production requires `FARO_SECRET_KEY_BASE` (at least 64 bytes), `FARO_DATABASE_URL`,
and `FARO_DATABASE_CA_FILE`. Database TLS verifies peers and hostnames. Local
PostgreSQL is optional via `FARO_DATABASE_ENABLED=true`; do not disable production
TLS verification. Never log credentials or commit production secrets.

Use `Faro.Schema` for new schemas so primary and foreign keys are UUIDs. Add
migrations under `priv/repo/migrations/`; a release init container applies them
before Phoenix starts. Readiness checks PostgreSQL when enabled and returns 503
on failure. Liveness must remain independent of PostgreSQL.

## Delivery

`Dockerfile` builds the release through Once and ships only the release and
runtime system libraries, running as an unprivileged user. Its Once checksums
must stay aligned with the root toolchain pin when updating Once.

`../deploy/helm/faro` defines the service at `https://faro.fyi`, using Caddy for
HTTPS, CloudNativePG for PostgreSQL, and the Barman plugin for daily backups and
continuous log archiving. Production targets the Pepicrft workload cluster. Live
Flux registrations are authoritative in `pepicrft/indie`, not duplicated here.
See `../deploy/README.md` for secrets, bootstrap prerequisites, and diagnostics.
No analytics events are emitted yet.
Only add safe named analytics events after meaningful product outcomes exist;
never include personal-agent content or credentials.
