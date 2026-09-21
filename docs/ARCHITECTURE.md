# Architecture

AstraBar (AppKit status item + SwiftUI popover) and astra-usage share UsageCore. No external package dependencies.

The live adapter executes codex app-server from a temporary working directory, inherits the user's environment and existing authentication, and performs a strict newline JSON handshake. It sends no inference request. Output is capped at 4 MiB and execution at 20 seconds; stderr is discarded. Successful responses are projected to quota-only models. Child cleanup uses bounded TERM then KILL if needed. Interactive server requests fail closed.

rateLimitsByLimitId is authoritative over duplicate legacy rateLimits entries. Names identify buckets; actual window duration determines the period. Missing data does not imply 100% available. A stale or expired snapshot is never automatically reset.

LogReader explicitly scans only the selected sessions directory, ignores symlinks, reads bounded tails and selects the latest event timestamp independently per bucket. File modification time only selects candidate files. Partial trailing events are ignored. Logs are not account-bound.

The UI serializes refreshes off the main thread, updates every 60 seconds and refreshes on wake. Source/path changes clear old snapshots. A failed query preserves old data only with historical labels and removes the menu percentage. There is no silent live-to-log fallback.

XCTest uses synthetic data and mock executables. Native build, protocol integration, native UI smoke and Intel execution are different verification layers and must be reported separately. Nothing here can reveal a hidden ChatGPT web/Astra quota.
