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

# Documentation reads only. Keep this outside the unrestricted host set.
allow if {
    input.operation == "fetch"
    input.method == "GET"
    input.url_parsed.scheme == "https"
    input.url_parsed.host == "docs.typesafe.ai"
    # url::Url normalizes an explicit default :443 to null.
    input.url_parsed.port in {null, 443}
}
