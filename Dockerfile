# pi-irc: the pi coding agent as an IRC bot, one mcp-js sandbox session per channel.
# Builds r33drichards/pi at a pinned commit and runs `pi irc`.
FROM node:22-bookworm-slim AS build
ARG PI_REPO=https://github.com/r33drichards/pi.git
ARG PI_COMMIT=de3d0a76543e21d00f4cf577b888d454d6da76b1
# Space-separated pi packages baked into the image's agent directory. Sessions
# run on pi's normal runtime, so any extension from the pi registry works.
ARG PI_EXTENSIONS="npm:pi-schedule-prompt"
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
RUN git clone --filter=blob:none "$PI_REPO" . && git checkout --quiet "$PI_COMMIT" \
 && rm -rf .git
# Use the matching release's model-data snapshot, verified before extraction.
# Live catalog generation can remove providers or introduce unsupported APIs even
# when PI_COMMIT is pinned. Only JSON data is extracted; Pi's source stays pinned.
ADD --checksum=sha256:af7d11986179445ce6fe88b37d57de22f823c0ffd3a65cae31c555b7f5e99253 https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-0.85.1.tgz /tmp/pi-ai.tgz
RUN tar -xzf /tmp/pi-ai.tgz -C packages/ai/src/providers --strip-components=3 package/dist/providers/data \
 && rm /tmp/pi-ai.tgz
COPY scripts/prepare-model-data.mjs /tmp/prepare-model-data.mjs
RUN node /tmp/prepare-model-data.mjs /app && rm /tmp/prepare-model-data.mjs
# Dev dependencies stay: pi irc runs from source through tsx.
# --ignore-scripts skips native builds unused here.
RUN npm ci --ignore-scripts --no-audit --no-fund && npm run build:offline && npm cache clean --force
# Extensions are installed into a seed agent directory, not /data/agent: that
# path is a volume at runtime and would hide anything baked into the image.
RUN if [ -n "$PI_EXTENSIONS" ]; then \
      for package in $PI_EXTENSIONS; do \
        PI_CODING_AGENT_DIR=/opt/pi-agent-seed /app/pi-test.sh install "$package"; \
      done; \
    fi

FROM node:22-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates && rm -rf /var/lib/apt/lists/*
ENV PI_CODING_AGENT_DIR=/data/agent \
    NODE_ENV=production
COPY --from=build /app /app
COPY --from=build /opt/pi-agent-seed /opt/pi-agent-seed
COPY entrypoint.sh /usr/local/bin/pi-irc-entrypoint
RUN chmod +x /usr/local/bin/pi-irc-entrypoint && mkdir -p /data/agent /workspace
WORKDIR /workspace
ENTRYPOINT ["pi-irc-entrypoint"]
