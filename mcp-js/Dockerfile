# The dedicated mcp-js engine for pi-irc, configured by mcp-js/config.toml.
# Railway builds this from the repo (dockerfile path mcp-js/Dockerfile, root /);
# compose mounts the same directory instead of building.
FROM wholelottahoopla/mcp-js:0.21.0-rc.2
COPY --chown=mcpuser:mcpuser mcp-js/ /config/
ENV MCP_V8_CONFIG=/config/config.toml
