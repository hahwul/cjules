##= BUILDER =##
FROM crystallang/crystal:1.20.0 AS builder
WORKDIR /cjules

RUN apt-get update && \
    apt-get install -y --no-install-recommends libyaml-dev pkg-config && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY shard.yml shard.lock ./
RUN shards install --production

COPY . .
RUN shards build --release --no-debug --production && \
    strip /cjules/bin/cjules

##= RUNNER =##
FROM debian:13-slim

LABEL org.opencontainers.image.title="cjules"
LABEL org.opencontainers.image.description="Crystal CLI for the Jules API with multi-account support, bulk ops, watch mode, and gitPatch extraction."
LABEL org.opencontainers.image.authors="hahwul <hahwul@gmail.com>"
LABEL org.opencontainers.image.source="https://github.com/hahwul/cjules"
LABEL org.opencontainers.image.documentation="https://github.com/hahwul/cjules"
LABEL org.opencontainers.image.licenses="MIT"

ENV LC_ALL=C.UTF-8
ENV LANG=en_US.UTF-8

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libyaml-0-2 \
        ca-certificates \
        git && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=builder /cjules/bin/cjules /usr/local/bin/cjules

ENTRYPOINT ["cjules"]
CMD ["--help"]
