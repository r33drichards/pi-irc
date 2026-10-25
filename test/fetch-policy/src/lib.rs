#[cfg(test)]
mod tests {
    use serde_json::{json, Value};

    // Mirrors mcp-js v0.21.0-rc.2 fetch.rs: do_fetch's URL fields and the
    // JavaScript fetch shim's uppercase method. Use that release's vendored
    // url crate; see README.md for the required Cargo patch configuration.
    fn input(method: &str, address: &str) -> Value {
        let parsed = url::Url::parse(address).unwrap();
        json!({
            "operation": "fetch", "url": address, "method": method.to_uppercase(), "headers": {},
            "url_parsed": {
                "scheme": parsed.scheme(), "host": parsed.host_str().unwrap_or(""),
                "port": parsed.port(), "path": parsed.path(), "query": parsed.query().unwrap_or("")
            }
        })
    }

    fn allowed(input: Value) -> bool {
        let mut engine = regorus::Engine::new();
        engine.add_policy("fetch.rego".into(), include_str!("../../../mcp-js/policies/fetch.rego").into()).unwrap();
        engine.set_input(regorus::Value::from_json_str(&input.to_string()).unwrap());
        engine.eval_rule("data.mcp.fetch.allow".into()).unwrap() == regorus::Value::Bool(true)
    }

    #[test]
    fn permits_only_documentation_reads_on_https_default_port() {
        for address in ["https://docs.typesafe.ai/", "https://docs.typesafe.ai:443/guide?q=1", "https://DOCS.TYPESAFE.AI/guide"] {
            assert!(allowed(input("GET", address)), "{address}");
        }
        assert!(allowed(input("get", "https://docs.typesafe.ai/")));
    }

    #[test]
    fn checks_real_url_parser_port_normalization() {
        assert_eq!(input("GET", "https://docs.typesafe.ai/")["url_parsed"]["port"], Value::Null);
        assert_eq!(input("GET", "https://docs.typesafe.ai:443/")["url_parsed"]["port"], Value::Null);
        assert_eq!(input("GET", "https://docs.typesafe.ai:8443/")["url_parsed"]["port"], 8443);
    }

    #[test]
    fn denies_other_methods_schemes_ports_and_hosts() {
        for method in ["POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS", "CONNECT"] {
            assert!(!allowed(input(method, "https://docs.typesafe.ai/")), "{method}");
        }
        for address in [
            "http://docs.typesafe.ai/", "http://docs.typesafe.ai:443/", "ftp://docs.typesafe.ai/",
            "https://docs.typesafe.ai:80/", "https://docs.typesafe.ai:8443/", "https://docs.typesafe.ai:0/",
            "https://www.docs.typesafe.ai/", "https://sub.docs.typesafe.ai/", "https://docs.typesafe.ai.evil.example/",
            "https://evildocs.typesafe.ai/", "https://docs.typesafe.ai@evil.example/", "https://docs.typesafe.ai./",
            "https://evil.example/?next=https://docs.typesafe.ai/"
        ] {
            assert!(!allowed(input("GET", address)), "{address}");
        }
    }

    #[test]
    fn missing_fields_and_other_operations_fail_closed() {
        let base = input("GET", "https://docs.typesafe.ai/");
        for key in ["scheme", "host", "port"] {
            let mut value = base.clone();
            value["url_parsed"].as_object_mut().unwrap().remove(key);
            assert!(!allowed(value), "missing {key}");
        }
        for key in ["method", "operation"] {
            let mut value = base.clone();
            value.as_object_mut().unwrap().remove(key);
            assert!(!allowed(value), "missing {key}");
        }
        let mut value = base;
        value["operation"] = json!("connect");
        assert!(!allowed(value));
    }

    #[test]
    fn preserves_every_previous_host_permission() {
        for host in ["github.com", "api.github.com", "codeload.github.com", "raw.githubusercontent.com",
            "objects.githubusercontent.com", "esm.sh", "cdn.jsdelivr.net", "unpkg.com"] {
            assert!(allowed(input("GET", &format!("https://{host}/"))), "{host}");
            assert!(allowed(input("POST", &format!("https://{host}:8443/path"))), "{host}");
        }
    }
}
