#!/usr/bin/env bash
# Build the pi settings from the environment (or a mounted /config), wait for
# the mcp-js coordinator, then run `pi irc`.
#
#   MCP_JS_URL            mcp-js coordinator, e.g. http://mcp-js:3000   (required)
#   MCP_JS_NETWORK        the engine's fetch policy lets sessions out (default true)
#   MCP_JS_MODULES        the engine allows ES module URL imports    (default true)
#   PI_DEFAULT_PROVIDER   provider id, e.g. anthropic                   (default anthropic)
#   PI_DEFAULT_MODEL      model id, e.g. claude-sonnet-5                (default claude-sonnet-5)
#   PI_MODELS_JSON        optional models.json contents for custom providers
#   IRC_*                 see README
set -euo pipefail
mkdir -p /data/agent /workspace/.pi
if [[ -f /config/settings.json ]]; then
  cp /config/settings.json /workspace/.pi/settings.json
else
  : "${MCP_JS_URL:?MCP_JS_URL must be set (the mcp-js coordinator URL)}"
  cat > /workspace/.pi/settings.json <<JSON
{
  "mcpJs": { "mode": "coordinator", "url": "${MCP_JS_URL}", "network": ${MCP_JS_NETWORK:-true}, "modules": ${MCP_JS_MODULES:-true} },
  "defaultProvider": "${PI_DEFAULT_PROVIDER:-anthropic}",
  "defaultModel": "${PI_DEFAULT_MODEL:-claude-sonnet-5}"
}
JSON
fi
if [[ -f /config/models.json ]]; then
  cp /config/models.json /data/agent/models.json
elif [[ -n "${PI_MODELS_JSON:-}" ]]; then
  printf '%s\n' "$PI_MODELS_JSON" > /data/agent/models.json
fi
url=$(sed -n 's/.*"url": *"\([^"]*\)".*/\1/p' /workspace/.pi/settings.json | head -1)
for i in $(seq 1 60); do
  if curl -fsS "${url%/}/api/capabilities" >/dev/null 2>&1; then break; fi
  echo "waiting for mcp-js at $url ($i)"; sleep 2
done
args=()
if [[ -n "${PI_WEB_PORT:-}" ]]; then args+=(--web-port "$PI_WEB_PORT"); fi
if [[ -n "${PI_WEB_TOKEN:-}" ]]; then args+=(--web-token "$PI_WEB_TOKEN"); fi
export PI_WEB_HOST="${PI_WEB_HOST:-0.0.0.0}"
exec /app/pi-test.sh irc "${args[@]}" "$@"
