ARG ELIXIR_VERSION=1.20.1
ARG OTP_VERSION=29.0.2
ARG DEBIAN_VERSION=trixie-20260610-slim
FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION} AS builder

ARG TARGETARCH
ARG ONCE_VERSION=0.68.2
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential ca-certificates curl git libasound2t64 \
    && rm -rf /var/lib/apt/lists/*
# Check the published archive against the hashes in the repository's mise.lock.
RUN case "$TARGETARCH" in \
      amd64) triple=x86_64-unknown-linux-gnu; checksum=04e4642205953c529c46e427f7dbaa478fc07b66f231dd147dc6c1641cb6a7d3 ;; \
      arm64) triple=aarch64-unknown-linux-gnu; checksum=7d19d71c1d533de15c9fde2b76ac7aaa6a963108a884b32b1149f0075bb7b2d1 ;; \
      *) echo "Unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac \
    && curl -fsSL "https://github.com/tuist/once/releases/download/${ONCE_VERSION}/once-${ONCE_VERSION}-${triple}.tar.gz" -o /tmp/once.tar.gz \
    && printf '%s  /tmp/once.tar.gz\n' "$checksum" | sha256sum -c - \
    && tar -xzf /tmp/once.tar.gz -C /usr/local/bin once \
    && rm /tmp/once.tar.gz

WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force
COPY mix.exs mix.lock ./
RUN mix deps.get --check-locked
# The image already supplies the exact compiler versions. Do not copy mise's
# developer tool configuration and install a second compiler inside the image.
COPY once.toml .formatter.exs ./
COPY config config
COPY lib lib
COPY priv priv
COPY test test
RUN once build mix_release

FROM debian:${DEBIAN_VERSION} AS runner
LABEL org.opencontainers.image.source="https://github.com/pepicrft/faro"
LABEL org.opencontainers.image.licenses="MIT"
RUN apt-get update && apt-get install -y --no-install-recommends \
      libstdc++6 openssl libncurses6 ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder --chown=65534:65534 /app/.once/out/mix_release/release ./
ENV LANG=C.UTF-8 HOME=/tmp PHX_SERVER=true PORT=4000 \
    ERL_CRASH_DUMP=/tmp/erl_crash.dump RELEASE_DISTRIBUTION=none
USER 65534:65534
EXPOSE 4000
CMD ["/app/bin/faro", "start"]
