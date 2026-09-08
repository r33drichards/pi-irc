package mcp.modules

# ES module imports from the ESM CDNs only. `npm:` specifiers resolve to esm.sh
# and are classified as specifier_type "npm", so gate on the resolved host.
default allow = false

allowed_hosts := {"esm.sh", "cdn.jsdelivr.net", "unpkg.com"}

allow if {
    input.url_parsed.host == allowed_hosts[_]
}
