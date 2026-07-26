# Driver Bridge to AVM PitWall local IPC options

**Status: RESEARCH — PROPOSED DIRECTION, NOT IMPLEMENTED**

The local IPC boundary carries low-rate presentation snapshots, commands,
acknowledgements, and health—not the high-volume telemetry stream. The Driver
Bridge remains the owner of shared-memory capture, server reconnection, session
recording, and setup files.

## Installed SDK evidence

| Option | Documented surface | Strengths | Risks / limits | F0 disposition |
| --- | --- | --- | --- | --- |
| CSP typed shared structure | `ac.connect()` in `ac_apps/lib.lua:7172-7182` | Low overhead; typed; suitable for frequent local state | Both sides need an exactly matched layout; external-process interoperability requires proof | **Preferred probe** |
| CSP shared events | `ac.broadcastSharedEvent()` / `ac.onSharedEvent()` at `3894-3914` | Natural for small asynchronous events | Delivery, replay, size, and external-process support need proof | Candidate for notifications |
| CSP Lua/Python storage | `ac.store()` / `ac.load()` at `3960-3973` | Simple, session-scoped exchange | Explicitly unsuitable for heavy traffic; C# bridge applicability unknown | Reject as primary transport |
| HTTP or WebSocket | `web.*` at `7895-7937` | Familiar contracts; bridge can host loopback endpoint | More moving parts; CSP permissions, lifecycle, security, and reconnect behavior need real testing | Strong fallback candidate |
| Memory-mapped file | Generic SDK includes read/write mapped-file surfaces | Cross-process and efficient | Synchronization, torn reads, ACLs, layout versioning, and cleanup become AVM responsibilities | Candidate for controlled POC |
| Shared texture handle | `ui.SharedTexture()` and cross-process handles at `9706-9732,10788-10792` | Useful for image transfer | Wrong abstraction for commands and structured state | Out of scope for core IPC |
| Process execution | `os.execute()` at `4473-4480` | Escape hatch | Unsafe lifecycle and command-injection surface; poor ownership boundary | Do not use |

## Recommended F2/F5 evaluation order

1. Prove whether a CSP app and the C# Driver Bridge can safely share an
   explicitly ordered, versioned structure using the installed CSP build.
2. In parallel, prototype a loopback-only HTTP/WebSocket fallback with strict
   origin, authentication, payload-size, and timeout controls.
3. Select one primary transport using measured latency, reconnect behavior,
   deployment friction, and CSP runtime evidence.
4. Keep the command envelope and state snapshot transport-neutral so the choice
   can change without moving domain ownership into Lua.

## Required local protocol properties

- explicit protocol and layout version;
- session and car identity on every snapshot or command;
- sequence and capture time;
- bounded payload sizes and strings;
- stale-state timeout;
- atomic snapshot or framing rule;
- idempotency key for commands and acknowledgements;
- health heartbeat and visible degraded state;
- loopback-only network binding if a socket transport is used;
- no secrets that a CSP UI must persist.

`ac.connect()` is a documented candidate, not an approved C# interoperability
contract. F2 must prove the bridge-side mechanism before ADR acceptance. See
[Driver Bridge boundary](../architecture/component-boundaries.md) and
[offline and reconnect model](../architecture/offline-and-reconnect-model.md).
