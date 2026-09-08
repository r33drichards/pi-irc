# pi-irc: the pi coding agent as an IRC bot, one mcp-js sandbox session per channel.
# Builds r33drichards/pi at a pinned commit and runs `pi irc`.
FROM node:22-bookworm-slim AS build
ARG PI_REPO=https://github.com/r33drichards/pi.git
ARG PI_COMMIT=862986d44b6de0ec9074a47fdd231c6a15293a16
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
RUN git clone --filter=blob:none "$PI_REPO" . && git checkout --quiet "$PI_COMMIT" \
 && rm -rf .git
# Dev dependencies stay: pi irc runs from source through tsx.
# --ignore-scripts skips native builds unused here.
RUN npm ci --ignore-scripts --no-audit --no-fund && npm run build && npm cache clean --force

FROM node:22-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates && rm -rf /var/lib/apt/lists/*
ENV PI_EXPERIMENTAL=1 \
    PI_CODING_AGENT_DIR=/data/agent \
    PI_SERVER_DIR=/tmp/pisrv \
    NODE_ENV=production
COPY --from=build /app /app
COPY entrypoint.sh /usr/local/bin/pi-irc-entrypoint
RUN chmod +x /usr/local/bin/pi-irc-entrypoint && mkdir -p /data/agent /tmp/pisrv /workspace
WORKDIR /workspace
ENTRYPOINT ["pi-irc-entrypoint"]
