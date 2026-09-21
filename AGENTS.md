# AstraBar

This is an independent public Swift package, not part of its parent repository.
- Build: `swift build`. Test: `swift test` with full Xcode on macOS, or Swift on Linux.
- Package: `bash scripts/package.sh`. Public release scope is this Git root only, `main`, MIT.
- Never publish real account responses, session logs, credentials, account identifiers, private screenshots, or parent history. Tests must use synthetic data.
- Codex protocol messages are restricted to initialize, initialized, account/rateLimits/read. Never start a model turn, invoke MCP, change auth or consume reset credits.
- Keep buckets separate. Codex, reserve and Spark are not Astra. Detect weekly by 10080 minutes, not primary/secondary. Never infer conversations remaining.
- Retain bounded reads, timeout cleanup, explicit offline log mode and stale/expired warnings.
