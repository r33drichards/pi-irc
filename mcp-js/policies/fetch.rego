package mcp.fetch

# Network access for sandbox sessions: git hosting and ESM CDNs only.
default allow = false

allowed_hosts := {
    "github.com",
    "api.github.com",
    "codeload.github.com",
    "raw.githubusercontent.com",
    "objects.githubusercontent.com",
    "esm.sh",
    "cdn.jsdelivr.net",
    "unpkg.com",
}

allow if {
    input.url_parsed.host == allowed_hosts[_]
}
