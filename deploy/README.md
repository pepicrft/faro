# Deploying Faro's server

Faro follows Gesttalt's delivery model:

1. `.github/workflows/server.yml` validates the server and chart and smoke-tests
   a relocated production release.
2. The image job builds for Linux amd64 and arm64. Only successful main-branch
   pushes or manual main-branch runs publish `ghcr.io/pepicrft/faro-server:main`
   and an immutable commit tag. Pull requests build without publishing.
3. Flux in `pepicrft/indie` tracks this repository's chart and the `main` image
   digest, records image changes in Git, and reconciles into the **Pepicrft
   workload cluster**.

This repository contains the application, chart, production values, and a staged
cluster-registration handoff under `deploy/indie/`. Nothing has been applied,
published, committed to `../indie`, or deployed by the scaffold setup.

## Scope

The chart runs the Phoenix release as an unprivileged user with a read-only root
filesystem, a bounded temporary volume, separate startup/liveness/readiness
probes, resource requests/limits, and a network policy. It disables Kubernetes
service-account token mounting and Elixir distribution. The production values
select the existing `app` node pool and External Secrets store.

The service is **ClusterIP-only**. No public domain, load balancer, TLS
certificate, database, storage claim, or model credential is created. A public
endpoint needs a domain and authentication design; do not expose future agent
operations merely by adding an ingress. No database or migrations are needed for
these stateless health/status endpoints.

## First deployment prerequisites

Before registering or unsuspending the release:

- Push the Faro repository and enable GitHub Actions. Allow its workflow token to
  publish packages, or provide `GHCR_PUSH_TOKEN` with the appropriate package
  access. The package is `faro-server`, not the native application executable.
- Run the server workflow successfully to publish the first image. Ensure the
  cluster's existing registry credential can pull it. For public distribution,
  set the package's visibility appropriately; a newly created package may be private.
- Provision `faro/SECRET_KEY_BASE` in the existing Infisical store, using at least
  64 random bytes/characters, for example generated with `openssl rand -hex 64`.
  Do not put its value into this repository or Helm command-line arguments.
  The chart synchronizes it as `faro-app-env` with a `FARO_SECRET_KEY_BASE` key.
- Confirm the existing `kubernetes/GHCR_PULL_USERNAME` and
  `kubernetes/GHCR_PULL_TOKEN` entries are readable by the workload cluster's
  External Secrets identity. They create `ghcr-pull-secret` in Faro's namespace.
- Confirm the platform release, management-cluster Flux controllers, and existing
  workload-cluster credentials are available. Keep their immutable legacy names
  (`org-salibu`, `salibu-production-kubeconfig`, and the `salibu-production` store
  alias); do not rename live infrastructure to add Faro.

Secret values are not part of image compilation or cached build actions. Rotating
runtime environment secrets requires a pod restart or a new rollout.

## Register in indie

The files under `deploy/indie/infra/` mirror their intended paths under the sibling
`../indie/infra/` directory. Apply them as a separate, reviewed infrastructure
change rather than applying resources directly to a live cluster:

1. Add `faro-source.yaml` and `faro-image-automation.yaml` to
   `infra/k8s/mgmt/flux/` and register both in that directory's `kustomization.yaml`.
2. Add the `faro-production/` directory to `infra/k8s/workload-apps/` and add
   `faro-production` to its parent `kustomization.yaml` resources.
3. Register the namespace in
   `infra/k8s/clusters/workloads/pepicrft/analytics-projects.yaml`, appending this
   document inside the existing `data.projects.yaml` block:

   ```yaml
   ---
   apiVersion: v1
   kind: Namespace
   metadata:
     name: faro
     labels:
       analytics.pepicrft.me/enabled: "true"
       infrastructure.pepicrft.com/project: faro
   ```

   This lets the cluster definition reconcile the namespace and its write-only
   `analytics-client` Secret, as required for new first-party projects. The Faro
   chart's analytics binding stays disabled until there are meaningful product
   events. Never send message content, credentials, personal data, or analytics
   read/admin credentials to the application or browser.
4. Review/build the affected Kustomize trees using indie's existing validation
   commands. Merge the registration while the HelmRelease is still suspended.
5. Confirm the image policy has resolved a real digest, then set
   `spec.suspend: false` in the infrastructure repository once prerequisites are
   ready. Flux will perform the rollout. Do not merge a fabricated image digest.

The staged HelmRelease intentionally begins suspended. Its source references the
public Git repository; if Faro remains private, configure a Git source credential
in indie before activation. Image automation updates only
`infra/k8s/workload-apps/faro-production`, keeping image digests reviewable there.

Once installed, the internal endpoint is `http://faro.faro.svc.cluster.local`.
Health routes are `/health/live` and `/health/ready`; `/api/v1/status` explicitly
reports that the agent runtime is not configured.

## Validate locally

From the Faro repository root:

```sh
mise -C server install github:tuist/once erlang elixir helm
mise -C server run setup
mise run check:server
mise -C server run smoke
mise run check:helm
```

With a running Docker engine and Buildx:

```sh
docker buildx build --platform linux/arm64 --load -t faro-server:local server
```

The Docker build uses Once 0.68.2, verifies its downloaded binary against the
pinned release checksum, and assembles the release through Once. Builder and
runtime use the same Debian generation. The final image contains neither the
source tree nor compilers. The separate `server/mise.toml` pins Elixir/Erlang to
the same versions as the builder.

Locally verified on Apple Silicon: Once graph validation, formatting, five
server tests, release assembly, HTTP probing after relocating the release, Helm
lint/rendering, and workflow/shell linting. No container engine was running, so
the Linux container image and live Flux reconciliation were not exercised here.
