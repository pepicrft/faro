# Faro deployment

Faro runs in the **Pepicrft workload cluster**, with its own `faro` namespace,
PostgreSQL database, and backup bucket. The chart and production values live here;
the live Flux registrations live in
[`pepicrft/indie`](https://github.com/pepicrft/indie):

- `infra/k8s/mgmt/flux/faro-source.yaml`
- `infra/k8s/mgmt/flux/faro-image-automation.yaml`
- `infra/k8s/workload-apps/faro-production/faro-helmrelease.yaml`
- `infra/k8s/clusters/workloads/pepicrft/analytics-projects.yaml`

These are the authoritative registrations, not a second copy in this repository.
Keep the immutable live aliases `org-salibu`, `salibu-production`, and
`salibu-production-kubeconfig`; they refer to existing Pepicrft resources.

## Public endpoint

A dedicated Hetzner load balancer exposes ports 80 and 443. External DNS creates
`faro.fyi` records in Cloudflare, with proxying disabled. The platform's domain
allowlist must include `faro.fyi`. Cloudflare must be authoritative at the registrar.

An unprivileged Caddy container terminates HTTPS, obtains and renews certificates
using Let's Encrypt, redirects HTTP, and proxies to Phoenix's internal ClusterIP
service. Its certificate state is persisted on a 2 GiB volume. Phoenix itself is
not publicly exposed. The root and `/api/v1/status` return service metadata;
`/health/live` checks the application and `/health/ready` also queries PostgreSQL.
There is no agent runtime, account system, or personal-content API yet.

## Database and backups

The chart provisions a dedicated CloudNativePG PostgreSQL 18 cluster, using the
existing operator. This is **one instance**, not a highly available database. Its
20 GiB volume is scheduled onto the stateful node pool. Connections from Faro use
TLS with peer and hostname verification against the cluster's certificate authority.
An init container runs `Faro.Release.migrate()` before each web container starts;
Ecto serializes concurrent migration attempts. New schemas use UUID keys.

Backups follow the Gesttalt pattern:

- An `ObjectBucketClaim` provisions `pepicrft-faro-postgres-backups` and its scoped
  credentials through the existing object-storage controller.
- The Barman plugin continuously archives write-ahead logs to Hetzner S3 storage.
- A `ScheduledBackup` takes a base backup immediately, then daily at 02:30 UTC.
- Backups use gzip compression and a 30-day retention policy.
- The bucket has `Retain` reclamation behavior. Uninstalling the chart must not
  delete backups. Restoring still requires an explicit, tested recovery procedure.

Inspect actual backup completion, not just the schedule's existence:

```sh
KUBECONFIG="$HOME/.kube/pepicrft.yaml" kubectl -n faro get clusters.postgresql.cnpg.io
KUBECONFIG="$HOME/.kube/pepicrft.yaml" kubectl -n faro get objectbucketclaims,scheduledbackups,backups
```

## Secrets

Provision these **new, Faro-specific** entries in the existing Infisical project
used by `salibu-production` (currently environment `dev`, an existing cluster
configuration name, not the Faro deployment environment):

| External Secrets key | Purpose |
| --- | --- |
| `faro/SECRET_KEY_BASE` | Random signing key, at least 64 bytes |
| `faro/POSTGRES_PASSWORD` | Random password for the Faro database owner |

Never reuse another application's values. External Secrets creates `faro-app-env`
(including the encoded database URL) and `faro-postgres-app` (database bootstrap
credentials). The application mounts only the database's public CA certificate.

Existing `kubernetes/GHCR_PULL_USERNAME` and `kubernetes/GHCR_PULL_TOKEN` entries
provide image-pull credentials. The platform's namespace labels distribute only
`SMOLANALYTICS_HOST` and `SMOLANALYTICS_WRITE_KEY` through `analytics-client`;
no read key or user content is exposed. The server does not emit analytics yet.

Do not commit secrets, put them in Helm values, or log their contents. Missing
Infisical entries must be provisioned before enabling the HelmRelease.

## Automatic delivery

`.github/workflows/server.yml` checks the server and chart, smoke-tests a relocated
release against PostgreSQL, and verifies release migrations. Only then does it
publish the `linux/amd64` and `linux/arm64` image to
`ghcr.io/pepicrft/faro-server`, with `main` and commit tags.

Flux reads this repository's `main` branch for the chart and production values.
Its `ImageRepository` scans GHCR; an `ImagePolicy` follows the **digest** of the
mutable `main` tag. An `ImageUpdateAutomation` commits digest changes to the
annotated `image.digest` field in **indie**, and Helm rolls out that immutable
image. No deployment workflow or Kubernetes credential is needed in Faro's CI.

For initial activation, keep `spec.suspend: true` until the image is published,
Infisical entries exist, and the namespace registration is reconciled. Set a real
published digest, then commit `spec.suspend: false` in indie. Later releases need
no manual digest editing. Image-pull and Git write credentials must remain valid.

```sh
KUBECONFIG="$HOME/.kube/pepicrft-mgmt.yaml" flux reconcile source git pepicrft-infra
KUBECONFIG="$HOME/.kube/pepicrft-mgmt.yaml" flux get images all -A
KUBECONFIG="$HOME/.kube/pepicrft-mgmt.yaml" flux get helmrelease faro-production -n org-salibu
curl -fsS https://faro.fyi/health/ready
```

## Local validation

```sh
mise run check:server
mise -C server run smoke
mise run check:helm
```

Local development and the default smoke test do not require PostgreSQL. To enable
it, set `FARO_DATABASE_ENABLED=true` and `FARO_DATABASE_URL`; production additionally
requires `FARO_DATABASE_CA_FILE` for verified TLS. `FARO_DATABASE_SSL=false` is only
for local or isolated CI databases. Set `FARO_SMOKE_DATABASE_ENABLED=true` to make
the release smoke test verify a configured database as CI does.
