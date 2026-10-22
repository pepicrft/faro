# Faro server

This is an independent Once workspace with a Phoenix/Bandit JSON service. It is
not an implemented agent backend. Boruta provides OAuth/OpenID Connect with public
native-client registration, mandatory S256 PKCE, browser accounts/consent, refresh
rotation, and revocation. See `AUTHENTICATION.md`. Native client sign-in and API
transport, model providers, and agent execution are not implemented. Health,
metadata, discovery, registration, and browser authentication are public; account
claims require a valid bearer token. Never add unauthenticated agent APIs.

## Development

From the repository root:

```sh
mise -C server install github:tuist/once erlang elixir helm
mise -C server run setup
# Configure FARO_TEST_DATABASE_URL to a disposable local PostgreSQL database first.
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
workaround here, not in a fork or modification of the Once installation. Use
explicit `run_tasks` for development and migrations: the authored runner registers
Once's prefetched dependency SCM, while generic Mix commands need unavailable Hex
archives in the isolated runtime home. Database migrations must remain non-cacheable.

Every ExUnit module must use `async: true`. Never change application environment
or other global state in a test. Test through explicit dependencies and the real
endpoint. Tests require `FARO_TEST_DATABASE_URL`, run migrations, and use private
SQL-sandbox ownership; never skip DB tests or use production credentials. Inject
rate-limiter namespaces through the test connection, not global configuration.
Enable real CSRF protection in browser tests; Phoenix.ConnTest disables it by
default. Treat liveness and readiness separately when adding external services.

Production requires `FARO_SECRET_KEY_BASE` (at least 64 bytes), `FARO_DATABASE_URL`,
and `FARO_DATABASE_CA_FILE`. Database TLS verifies peers and hostnames. Local
PostgreSQL is optional via `FARO_DATABASE_ENABLED=true`; do not disable production
TLS verification. Never log credentials or commit production secrets.

Keep browser identity (`Accounts`), OAuth policy/adapters (`Auth`), and HTTP adapters
separate. Register only allowlisted public clients; do not forward user-supplied
Boruta options, keys, or remote JWKS URLs. Require consent bound to a one-time
request ID and CSRF token. Serialize token mutations with per-client database
transaction advisory locks before credential row locks, so concurrent rotation
cannot escape replay protection or refresh-token revocation.
Retain the database-backed, non-caching Boruta adapter so revocation cannot remain
stale across replicas or escape test transactions. OAuth signing keys are generated
at runtime and stored in PostgreSQL, never in release/cache outputs. Email claims
must remain `email_verified: false` until a verification flow actually exists.

Use `Faro.Schema` for new schemas so primary and foreign keys are UUIDs. Add
migrations under `priv/repo/migrations/`; a release init container applies them
before Phoenix starts. Readiness checks PostgreSQL when enabled and returns 503
on failure. Liveness must remain independent of PostgreSQL.

## Delivery

The server shares Tuist project `pedrotuist/faro` and the native workspace's
Once authentication session. Use `ONCE_CACHE_PROVIDER=local` for offline builds.
Trusted CI checks use short-lived OpenID Connect credentials when the repository
variable `TUIST_CI_ENABLED=true`; never persist those credentials in build outputs.

`Dockerfile` builds the release through Once with the local cache provider and
ships only the release and runtime system libraries, running as an unprivileged
user. The host CI check job supplies Tuist insights and shared release caching;
BuildKit caches the separate multi-architecture image layers without credentials. Its Once checksums
must stay aligned with the root toolchain pin when updating Once.

`../deploy/helm/faro` defines the service at `https://faro.fyi`, using the shared
NGINX ingress and Certificate Manager for HTTPS, CloudNativePG for PostgreSQL,
and the Barman plugin for daily backups and
continuous log archiving. Production targets the Pepicrft workload cluster. Live
Flux registrations are authoritative in `pepicrft/indie`, not duplicated here.
See `../deploy/README.md` for secrets, bootstrap prerequisites, and diagnostics.
No analytics events are emitted yet.
Only add safe named analytics events after meaningful product outcomes exist;
never include personal-agent content or credentials.
