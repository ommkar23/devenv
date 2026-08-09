# Hermes home

This versioned baseline contains non-secret configuration and skills. It is
the only agent configuration home managed by this repository.

Ignored: API keys, OAuth tokens, sessions, logs, caches, and databases.

```bash
export HERMES_HOME=/workspace/devenv/.hermes
hermes auth add openai-codex --type oauth --no-browser
# Then run `hermes model` to select a provider and model.
```
