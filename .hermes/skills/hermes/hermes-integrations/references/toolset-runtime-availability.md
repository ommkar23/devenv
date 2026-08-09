# Toolset configuration versus active runtime availability

Use this when `hermes tools list` appears to disagree with the tools exposed in a conversation.

## Interpretation

- `hermes tools list` reports configured toolset enablement for a platform; without `--platform`, it reports `cli` and labels the section `Built-in toolsets (cli)`.
- A row is a **toolset** (a group of tools), not necessarily an individual callable tool.
- `✓ enabled` means the toolset is permitted for that platform. It does not by itself prove that every member is installed, credentialed, supported by the current environment, or injected into an already-running session.
- MCP entries are separate from built-ins. `SERVER  all tools enabled` means no discovered tools from that server are filtered out; it does not independently prove current connectivity.
- MCP call names use `mcp__<server>__<tool>` in the active schema.

## Reliable diagnostic sequence

1. Run `hermes tools list --help` to confirm supported platform names for the installed version.
2. Run `hermes tools list` and note the platform named in the heading; do not assume it describes ACP or every gateway surface.
3. Distinguish configuration from runtime capability:
   - configuration: what the CLI says is enabled for a platform;
   - active schema: tools actually exposed to the present agent session;
   - readiness: dependencies, credentials, connectivity, and environment support.
4. If a toolset was newly enabled or an MCP server newly added, start a new session before checking the active schema.
5. Explain any discrepancy narrowly: “enabled for platform X but not exposed in this active session,” rather than making a durable negative claim that the feature is unavailable in Hermes.

Authoritative reference: <https://hermes-agent.nousresearch.com/docs/reference/tools-reference>
