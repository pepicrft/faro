# Native-client authentication

Faro uses [Boruta](https://github.com/malach-it/boruta_auth) as an OAuth 2.0 and
OpenID Connect provider. Authentication identifies a local account; it does not
implement an agent runtime or connect the native welcome screens to the server.

## Endpoints

| Endpoint | Purpose |
| --- | --- |
| `GET /.well-known/openid-configuration` | OpenID Connect discovery |
| `GET /.well-known/oauth-authorization-server` | OAuth authorization-server metadata |
| `POST /oauth/register` | Public native-client registration (RFC 7591) |
| `GET /oauth/authorize` | Browser authentication and explicit consent |
| `POST /oauth/authorize` | CSRF-protected, request-bound consent decision |
| `POST /oauth/token` | Authorization-code exchange or refresh-token rotation |
| `POST /oauth/revoke` | Token revocation (RFC 7009) |
| `GET /oauth/jwks` | Public signing keys for ID-token verification |
| `GET/POST /oauth/userinfo` | Bearer-authenticated account claims |
| `GET /api/v1/me` | Alias for the authenticated account claims |
| `GET /auth/login` | Browser sign-in and account-creation forms |
| `POST /auth/login`, `/auth/register`, `/auth/logout` | CSRF-protected browser session operations |

The issuer comes from server configuration, not the request's Host header. It is
`https://$FARO_HOST` in production (default `https://faro.fyi`) and
`http://localhost:$PORT` in development. OAuth routes return 503 when the optional
development database is disabled. Discovery and database-independent liveness
remain available.

## Client flow

1. Choose the callback URI and register the installation as a **public native
   client**. No shared client secret is issued or embedded in the app.

   ```sh
   curl --fail-with-body http://localhost:4000/oauth/register \
     -H 'Content-Type: application/json' \
     -d '{"client_name":"Faro Desktop","application_type":"native","redirect_uris":["http://127.0.0.1:49152/callback"],"grant_types":["authorization_code","refresh_token"],"response_types":["code"],"token_endpoint_auth_method":"none","scope":"openid profile email"}'
   ```

   Register only redirect URIs the installation controls. Supported callbacks are
   HTTPS (ASCII/punycode hostnames or IP literals), IP-literal HTTP loopback (`127.0.0.1` or `[::1]`), and reverse-domain
   private schemes such as `io.github.pepicrft.faro:/oauth/callback`. Userinfo,
   fragments, backslashes, and wildcards are rejected. Matching is exact, including
   the loopback port: start/select the listener before registration, and register
   again if its callback changes. There is no client-registration management API.

2. Generate a cryptographically random 43–128-character PKCE verifier, a random
   state (at least 32 random bytes, encoded), and a random OpenID nonce. Keep them
   private to this authorization attempt. Compute
   `BASE64URL(SHA256(verifier))`, without padding, as the challenge.

3. Open the **system browser**, not an embedded password form, at the discovered
   authorization endpoint with `client_id`, the exact `redirect_uri`,
   `response_type=code`, `scope=openid profile email`, `state`, `nonce`,
   `code_challenge`, and `code_challenge_method=S256`.

4. The person signs in or creates a local account and explicitly allows or denies
   the request. Registration names are unverified metadata, not trusted app
   identities. Consent is bound to a one-time request ID, the encrypted session,
   and a CSRF token. A changed client/redirect in the consent POST cannot redirect
   the grant. Pending consent expires after ten minutes.

5. On callback, compare state with the saved value **before** consuming the code.
   Handle `error=access_denied` without exchanging a code. POST form-encoded or
   JSON `grant_type=authorization_code`, `client_id`, `code`, `redirect_uri`, and
   `code_verifier` to the token endpoint. Authorization codes expire after 60
   seconds and are single-use. Only S256 is accepted; plain PKCE, implicit,
   password, and client-credentials grants are not supported. Signed request
   objects, `request_uri`, `prompt`, and `max_age` are not supported.

6. Verify the ID token's RS256 signature using the discovered public JWKS,
   issuer, audience (`client_id`), expiration, and nonce. Send the **access
   token**, not the ID token, as `Authorization: Bearer <access_token>` to Faro's
   authenticated API. Userinfo always includes `sub`; `email` and
   `email_verified: false` appear only when the email scope was granted.

7. Store credentials in the OS credential store. Access and ID tokens last at
   most 15 minutes; refresh tokens last at most 30 days. Serialize refreshes per
   installation. Exchange `grant_type=refresh_token`, `client_id`, and
   `refresh_token`, then atomically replace the stored refresh token. Optional
   `scope` may narrow, never broaden, consent. Reusing a rotated refresh token
   revokes this client's grants for that account, including its descendants.
   Authorization-code replay also revokes those grants when the original PKCE
   verifier proves possession. After uncertain refresh completion or reuse errors,
   sign in again rather than blindly retrying the old credential.

8. On native sign-out, revoke the current refresh token with `client_id`, `token`,
   and `token_type_hint=refresh_token`, then erase local credentials. Revoking a
   refresh token also revokes this client's other grants for the account, including
   descendants of an already rotated token. Browser
   logout separately revokes the browser session; it is not a global OAuth logout
   endpoint.

## Persistence and security boundaries

All application keys and foreign keys are UUIDs. A release migration creates
accounts, hashed browser sessions, Boruta's tables, and the initial `openid`,
`profile`, and `email` scopes. Migrations do not create accounts, clients, or
signing keys. Boruta generates per-client RSA keys at registration and persists
them in PostgreSQL, so replicas/restarts use the same signing material.

Passwords use PBKDF2-HMAC-SHA512 with 210,000 iterations, a random salt, and a
15–128-character policy. Browser credentials are hashed in the database, encrypted
and signed in an HttpOnly, SameSite=Lax cookie, and marked Secure in production.
The server also checks session expiration and database revocation. Boruta's OAuth
tokens and private signing keys are sensitive database contents, not hashed
browser-session values: protect database access, TLS, and backups accordingly.
SQL query logging is disabled and authentication parameters are filtered from
Phoenix logs. Never copy database contents or generated keys into build outputs.

Token exchange and revocation take a PostgreSQL transaction advisory lock per
client before locking credential rows around Boruta's read/issue/revoke operations.
This prevents concurrent rotation from escaping grant-family revocation. Boruta's process cache is deliberately bypassed, so revocation is
visible across replicas immediately and cannot escape a test's transaction.
Deleted accounts cannot use or refresh their grants.

Rate limits are shared through PostgreSQL: ten registrations per minute per peer
IP and twenty globally, five account creations per minute per peer IP, ten sign-in
attempts per minute per peer IP, and 120 requests per minute per peer IP for each
other auth method/path. Counters expire after about 24 hours. The service uses the
transport peer IP and **does not trust arbitrary forwarding headers**. Behind the
shared ingress these limits conservatively apply to the proxy's peer IP until a
trusted-proxy boundary is explicitly configured; do not enable blanket trust of
`X-Forwarded-For`.

## Local development and tests

Development can still run health/status routes without PostgreSQL. Install/run
PostgreSQL 18 and its command-line tools separately from the mise toolchain. To use
auth, create a dedicated development database and enable it before migrating:

```sh
createdb faro_dev
export FARO_DATABASE_ENABLED=true
export FARO_DATABASE_URL="postgres://$(whoami)@localhost:5432/faro_dev"
export FARO_DATABASE_SSL=false  # local PostgreSQL only; production verifies TLS
mise -C server run db:migrate
mise run dev:server
```

Adjust the local PostgreSQL role/credentials for your installation. Use a separate,
disposable database for tests:

```sh
createdb faro_test
export FARO_TEST_DATABASE_URL="postgres://$(whoami)@localhost:5432/faro_test"
mise run check:server
```

Tests always require PostgreSQL, automatically migrate that database, and use
async SQL-sandbox ownership. There is no database-disabled skip mode that could
publish incomplete test results to shared caching. Once inherits only
`FARO_TEST_DATABASE_URL` for tests; never point it at a production database or
supply production credentials. GitHub Actions supplies an ephemeral PostgreSQL
service and its CI-only credentials. Development and production releases continue
to read `FARO_DATABASE_URL` separately.

## Deliberate limits

There is no email delivery, email verification, password recovery, MFA, account
management/deletion UI, or upstream identity-provider login yet. Email addresses
are self-asserted, never verified identity claims. Do not grant access to anything
based on an email address matching another account. The stable UUID `sub` is the
account identity. Native client sign-in UI, callback handlers, token verification,
OS credential storage, and authenticated API transport remain future work.

Deploying this change enables public account creation and client registration.
Review these limits before production rollout; implementing and locally validating
authentication does not authorize a deployment.
