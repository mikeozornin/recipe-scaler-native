<!--
Sync Impact Report
- Version change: (none) → 1.0.0
- Modified principles: N/A (initial ratification from template)
- Added sections: Core Principles (5), Technology Constraints, Development Workflow & Quality Gates, Governance
- Removed sections: Template placeholders
- Templates requiring updates:
  - ✅ .specify/templates/plan-template.md (Constitution Check gates)
  - ✅ .specify/templates/spec-template.md (sync/schema alignment note)
  - ✅ .specify/templates/tasks-template.md (constitution-driven task categories)
  - ✅ README.md (constitution reference)
- Follow-up TODOs: none
-->

# Recipe Scaler Native Constitution

## Core Principles

### I. CRDT-First Data Model

All synced recipe data MUST live in `Y.Doc` instances managed by **yrs** (Rust via C FFI).
SQLite stores Y state snapshots, `lastSyncedAt`, and the offline operation queue — not
authoritative recipe content. REST endpoints are auxiliary (auth, images, public links).

**Rationale**: CRDT is the convergence layer shared with the web client and backend.
Duplicating recipe state in parallel models causes drift and manual conflict resolution.

### II. Web Client Parity (NON-NEGOTIABLE)

The iOS app MUST remain binary-compatible with **Yjs 13.6.30** on the server and mirror
the web client's sync contract:

- Document keys and structure per [docs/YJS-SCHEMA.md](../../docs/YJS-SCHEMA.md)
- Socket.IO events and payloads per [docs/ARCHITECTURE.md](../../docs/ARCHITECTURE.md)
- 1s debounced updates with merge semantics matching `yjs-client.ts`

Backend changes MUST NOT be required for native features. Schema or protocol changes MUST
be coordinated with the main Recipe Scaler web client first.

**Rationale**: One sync surface across platforms; the backend is shared and frozen for
native work.

### III. Offline-First Resilience

The app MUST remain usable when connectivity is degraded or absent. Local mutations MUST
be queued in SQLite and drained on reconnect. CRDT merge handles concurrent edits — manual
conflict resolution MUST NOT be introduced.

**Rationale**: Mobile usage is inherently intermittent; offline queue + CRDT is the
designed recovery path.

### IV. Native UI, Minimal WebView

All screens MUST use **SwiftUI**. **WKWebView** is permitted ONLY for the recipe
description block (Tiptap + custom nodes). Full-screen or navigation-level WebView shells
MUST NOT replace native UI.

**Rationale**: Native performance and platform UX for core flows; WebView cost is
isolated to rich text where rewriting Tiptap nodes is impractical.

### V. Phased, Independently Testable Delivery

Work MUST follow the phased roadmap in README and `RecipeScalerNative/PROJECT_STATUS.md`.
Each phase MUST deliver an independently testable increment. Scope from later phases MUST
NOT land early (YAGNI). Complexity beyond the current phase MUST be justified in the
plan's Complexity Tracking table.

**Rationale**: The project evolves REST → yrs read → native write → WebView description →
full sync parity; skipping phases breaks validation and risk management.

## Technology Constraints

| Area | Requirement |
|------|-------------|
| Platform | iOS 17.0+, Xcode 16.0+, Swift 5.9+ |
| CRDT engine | **yrs** via C FFI / XCFramework — not yswift, not JavaScriptCore for CRDT |
| Sync transport | socket.io-client-swift — same events as web |
| Local storage | SQLite (GRDB or SwiftData) for Y snapshots + offline queue |
| Auth | Seed-based (BIP39) + Keychain — same model as web |
| UI | SwiftUI; localization via i18n resource files — no hardcoded user-facing strings |
| Dependencies | SPM where possible; Xcode project maintained manually (see SETUP.md) |
| Documentation | Architecture/schema changes MUST update `docs/ARCHITECTURE.md`, `docs/YJS-SCHEMA.md`, and related guides |

Export/import features (when implemented) MUST include `metadata.version`, maintain backward
compatibility, and ship schema + validator artifacts per project export rules.

## Development Workflow & Quality Gates

1. **Constitution Check** — Every implementation plan MUST pass the gates in
   `.specify/templates/plan-template.md` before Phase 0 research and again after Phase 1
   design.
2. **Spec quality** — Feature specs MUST define prioritized, independently testable user
   stories with measurable success criteria (technology-agnostic).
3. **Tasks** — Generated tasks MUST map to user stories; foundational sync/schema work
   blocks story implementation when applicable.
4. **Documentation** — Code changes that affect architecture, schema, or setup MUST
   update the corresponding docs in the same change set.
5. **Testing** — XCTest and integration tests for sync/schema paths when the feature spec
   requests tests; contract tests required when Socket.IO or Y.Doc shape changes.
6. **Review** — PRs MUST verify: schema parity, i18n compliance, offline behavior where
   relevant, and no unauthorized backend coupling.

Runtime guidance: [AGENTS.md](../../AGENTS.md), [docs/ARCHITECTURE.md](../../docs/ARCHITECTURE.md),
[docs/YJS-SCHEMA.md](../../docs/YJS-SCHEMA.md), [SETUP.md](../../SETUP.md).

## Governance

This constitution supersedes ad-hoc technical decisions for Recipe Scaler Native.
Amendments MUST:

1. Be applied via `/speckit-constitution` with documented rationale
2. Bump `CONSTITUTION_VERSION` per semantic versioning (MAJOR: principle removal/redefinition;
   MINOR: new principle or material expansion; PATCH: clarifications)
3. Propagate changes to dependent Spec Kit templates and docs listed in the Sync Impact Report

All feature plans and reviews MUST verify compliance. Violations MUST be documented in
Complexity Tracking with justification, or resolved before merge.

**Version**: 1.0.0 | **Ratified**: 2026-06-01 | **Last Amended**: 2026-06-01
