#!/usr/bin/env bash
# Seed the agent directory (extensions baked into the image), write the pi
# settings from the environment or a mounted /config, wait for the mcp-js
# coordinator, then run `pi irc`.
#
#   MCP_JS_URL            mcp-js coordinator, e.g. http://mcp-js:3000   (required)
#   MCP_JS_NETWORK        the engine's fetch policy lets sessions out (default true)
#   MCP_JS_MODULES        the engine allows ES module URL imports    (default true)
#   PI_DEFAULT_PROVIDER   provider id, e.g. anthropic                   (default anthropic)
#   PI_DEFAULT_MODEL      model id, e.g. claude-sonnet-5                (default claude-sonnet-5)
#   PI_MODELS_JSON        optional models.json contents for custom providers
#   IRC_*                 see README
set -euo pipefail
mkdir -p /data/agent

# /data/agent is a volume, so the image's extensions are copied in on first
# boot. Later boots keep whatever is there, including anything installed since.
if [[ -d /opt/pi-agent-seed && ! -d /data/agent/npm ]]; then
  echo "seeding /data/agent with the image's extensions"
  cp -a /opt/pi-agent-seed/. /data/agent/
fi

if [[ -f /config/models.json ]]; then
  cp /config/models.json /data/agent/models.json
elif [[ -n "${PI_MODELS_JSON:-}" ]]; then
  printf '%s\n' "$PI_MODELS_JSON" > /data/agent/models.json
fi

# Settings go in the agent directory, not a project .pi: every channel session
# has its own working directory, and only the agent-level file is shared by
# all of them. Merge, so the extension list written by `pi install` survives.
if [[ -f /config/settings.json ]]; then
  SETTINGS_OVERLAY=$(cat /config/settings.json)
else
  : "${MCP_JS_URL:?MCP_JS_URL must be set (the mcp-js coordinator URL)}"
  SETTINGS_OVERLAY=$(cat <<JSON
{
  "mcpJs": { "mode": "coordinator", "url": "${MCP_JS_URL}", "network": ${MCP_JS_NETWORK:-true}, "modules": ${MCP_JS_MODULES:-true} },
  "defaultProvider": "${PI_DEFAULT_PROVIDER:-anthropic}",
  "defaultModel": "${PI_DEFAULT_MODEL:-claude-sonnet-5}"
}
JSON
)
fi
SETTINGS_OVERLAY="$SETTINGS_OVERLAY" node -e '
const { readFileSync, writeFileSync, existsSync } = require("node:fs");
const path = "/data/agent/settings.json";
const current = existsSync(path) ? JSON.parse(readFileSync(path, "utf8")) : {};
writeFileSync(path, `${JSON.stringify({ ...current, ...JSON.parse(process.env.SETTINGS_OVERLAY) }, null, 2)}\n`);
'

url=$(node -e 'console.log(JSON.parse(require("node:fs").readFileSync("/data/agent/settings.json","utf8")).mcpJs?.url ?? "")')
for i in $(seq 1 60); do
  if curl -fsS "${url%/}/api/capabilities" >/dev/null 2>&1; then break; fi
  echo "waiting for mcp-js at $url ($i)"; sleep 2
done
exec /app/pi-test.sh irc "$@"
