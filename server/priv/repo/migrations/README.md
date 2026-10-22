# Faro migrations

`20261021000100_create_authentication.exs` creates local accounts, hashed browser
sessions, Boruta's OAuth clients/tokens/scopes, and database-backed rate limits.
All primary and foreign keys are UUIDs (`:binary_id`), including the scope join
table. The only seeded data is the public `openid`, `profile`, and `email` scopes;
accounts, clients, credentials, and signing keys are never build-time seeds.

Release deployment runs `Faro.Release.migrate()` before Phoenix starts. Tests
migrate their separate disposable database before entering async SQL-sandbox
transactions. Add new versioned `.exs` migrations rather than editing an already
applied migration. See [the authentication flow](../../../AUTHENTICATION.md).
