# ADR-004: On-Prem Web Architecture

- Status: Proposed
- Date: 2026-07-26
- Related: [F3](../phases/F3-relay-server.md), [F4](../phases/F4-engineer-web.md), [F11](../phases/F11-reliability-and-security.md)

## Context

The target use case is team-operated endurance racing, where low-latency local control and predictable deployment matter more than multi-tenant cloud scale. The programme needs an architecture direction that matches that operational reality.

## Decision

Plan around an on-prem relay-plus-console deployment model. The proposed stack is .NET 10 for host-side services, ASP.NET Core plus SignalR for relay and session delivery, PostgreSQL for durable state when persistence is introduced, and SvelteKit plus TypeScript for the browser-based Engineer Console. This direction is proposed, must stay evidence-backed through the relay and console phases, and requires explicit owner approval before it is treated as locked.

## Consequences

- Deployment and troubleshooting stay within team-controlled infrastructure.
- Security, setup transfer, and rollback planning can target a concrete operational model.
- Future hosted options, if any, should be treated as a later architecture decision rather than assumed now.
- Stack substitutions remain allowed until owner approval, but they should be evaluated against on-prem fit, CSP compatibility, and delivery speed.

## Open Questions

- Whether setup transfer in F10 needs a packaged single-host path in addition to a split relay/web deployment.
