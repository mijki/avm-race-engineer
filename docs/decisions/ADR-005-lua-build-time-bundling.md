# ADR-005: Lua Build-Time Bundling

- Status: Proposed
- Date: 2026-07-26
- Related: [F1](../phases/F1-driver-client-shell.md), [F10](../phases/F10-setup-transfer.md), [CSP Runtime Gate](../testing/csp-runtime-gate.md)

## Context

PitWall must ship into a constrained Lua runtime where loose asset sprawl, dynamic dependency assumptions, and inconsistent packaging will increase operational failure risk.

## Decision

Plan for build-time bundling of Lua client assets and supporting resources. The runtime package should be deterministic, minimal, validated before reaching simulator environments, and must not depend on `require` or `dofile` at runtime. Dependency order should be generated deterministically during bundling so the same source tree produces the same client package shape.

## Consequences

- CSP deployment becomes easier to reason about and test.
- Build and release gates can verify the actual package shape instead of a loose source tree.
- Client-side extensibility must be designed around explicit packaging, not ad hoc runtime loading.
- Any future modularity must flow through the bundler rather than dynamic Lua inclusion.

## Open Questions

- Which non-code assets must be bundled versus generated during installation.
