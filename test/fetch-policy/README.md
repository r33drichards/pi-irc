# Fetch policy regression tests

These tests run the deployed Rego file through regorus 0.5.0, the evaluator
used by mcp-js v0.21.0-rc.2. They construct policy inputs with that release's
actual vendored URL parser (url 2.5.8), matching `server/src/engine/fetch.rs`
and its uppercase-method fetch shim. No HTTP requests or inference occur.

Check out `r33drichards/mcp-js` tag `v0.21.0-rc.2` in a separate directory
and verify commit `4b7daaff860fb660800b2567f1d753ef06908629`. Then run from
this repository, substituting its absolute path:

```sh
cargo test --locked --manifest-path test/fetch-policy/Cargo.toml \
  --config 'patch.crates-io.url.path="/absolute/mcp-js/server/vendor/url"'
```

Explicit HTTPS port 443 normalizes to null, just like an omitted port.
The policy allows only the exact docs host, HTTPS, GET, and null/443 ports.
Other hosts keep their prior permissions. Redirect destinations require a
separate policy check: the referenced engine disables automatic redirects.
