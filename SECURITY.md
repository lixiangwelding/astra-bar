# Security

AstraBar has no telemetry, remote backend or third-party dependencies. Live mode invokes a trusted, user-selected Codex executable and sends only initialize, initialized, account/rateLimits/read. Codex manages its own authentication and network behavior. Do not select untrusted executables.

Local log mode reads a bounded snapshot on explicit request. It cannot prove that a historical quota belongs to the current account. No raw conversations, authentication files, or account responses are persisted by AstraBar. UserDefaults stores only display/source/path preferences.

This app is not App-Sandbox isolated because it needs to execute an existing external CLI. Timeout and output limits are enforced, and child processes are cleaned up. Unexpected server requests fail closed.

Never post account logs, tokens, cookies, credentials, private screenshots, or prompts in a public issue. Describe problems with synthetic/redacted examples.

Releases are ad-hoc signed, not Developer ID signed or notarized. SHA-256 checks download integrity, not publisher identity. Do not disable global Gatekeeper.
