# Parallel Search MCP

Validated endpoint:

```yaml
mcp_servers:
  parallel_search:
    url: https://search.parallel.ai/mcp
    enabled: true
```

Installation command:

```bash
hermes mcp add parallel_search --url https://search.parallel.ai/mcp
```

During interactive discovery, the endpoint connected without authentication and exposed two tools:

- `web_search` — searches the web and returns LLM-oriented results.
- `web_fetch` — fetches and extracts relevant content from specific web pages.

Choose no authentication when the endpoint continues to support anonymous access, enable the desired tools, then verify:

```bash
hermes mcp list
hermes mcp test parallel_search
```

A validated setup returned a successful HTTP connection and discovered both tools. Hermes instructed that a new session was needed before those tools would enter the active tool schema.

Do not hard-code latency or assume anonymous access will remain permanent; trust the current discovery/auth behavior and official service requirements.
