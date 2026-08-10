# Specification Quality Checklist: Mac и iPad layout

**Purpose**: Validate specification completeness before implementation  
**Created**: 2026-07-01  
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs) — spec is behavior-focused; tech in plan.md
- [x] Focused on user value and business needs
- [x] Written for product/stakeholder review (Russian)
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic in spec (tech in plan)
- [x] All acceptance scenarios defined per user story
- [x] Edge cases identified
- [x] Scope clearly bounded (v1 out-of-scope listed)
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows (compact + wide + Mac)
- [x] Success criteria map to user stories
- [x] Web reference documented in spec header

## HIG / SwiftUI alignment (2026-07-01)

- [x] Regular shell uses `NavigationSplitView`, not custom web sidebar
- [x] Sidebar uses `List` / system style, collapsible
- [x] Recipes: selection-based 3-column split (Mail pattern)
- [x] Timers/assistant: toolbar/inspector, not web fixed columns
- [x] Compact: TabView unchanged; no bottom tabs in regular+sidebar
- [x] `horizontalSizeClass` primary trigger documented

## Interaction profile (2026-07-01)

- [x] `InteractionProfile` touch vs pointer documented
- [x] iPad: no hover-only actions; finger swipeActions preserved
- [x] macOS: trackpad swipe strips + hover where web group-hover
- [x] Same actions, different affordances (US11)
- [x] LayoutMode orthogonal to InteractionProfile

## Notes

- Prod screenshots pending — see `research.md` R6.
- `layout.md` requires human review before Swift UI.
- Web visual chrome explicitly deprioritized vs HIG in spec §«Платформенная модель».