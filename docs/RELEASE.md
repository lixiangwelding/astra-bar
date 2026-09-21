# AstraBar 0.1.0

Native macOS 13+ menu bar quota viewer. Download the Universal ZIP, extract and move AstraBar.app to Applications. A logged-in Codex CLI or compatible desktop executable is required. No API key input is needed.

Shows exposed quota percentages and reset times, not conversations remaining. Explicit Astra buckets are supported when returned by the server. Codex, reserve and Spark remain separate. Hidden Astra/ChatGPT web limits cannot be queried by this app.

## Assets

- AstraBar-0.1.0-macOS-universal.zip: Apple Silicon + Intel app.
- Matching .sha256: ZIP integrity checksum.
- astra-usage: companion Universal command-line executable.

## Signing and verification limits

The application is ad-hoc signed; it is not Apple Developer ID signed or notarized. macOS may require allowing this specific app in Privacy & Security after reviewing its source and checksum. Do not disable global Gatekeeper. Intel cross-compilation is not Intel hardware testing. Login-item behavior depends on installation and system approval.

## Maintainer release process

Use this independent Git root and main branch only. Stage only reviewed source, tests, docs and scripts; never parent project files or private evidence. Run `python3 scripts/audit_public.py`, macOS `swift build`, `swift test` with full Xcode (or verified macOS CI), Universal packaging, real read-only quota validation and native UI smoke. Inspect failure/unknown states too. A passing build alone is not runtime verification.

Verify the public target lixiangwelding/astra-bar and authenticated owner, push the reviewed commit, wait for its CI result, then tag that exact commit. Publish ZIP/checksum/CLI to the new tag without overwriting an existing release. Re-read the release metadata and verify checksum/asset size. Preserve private live evidence outside Git.
