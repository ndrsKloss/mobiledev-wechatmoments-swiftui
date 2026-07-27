# WeChat Moments — Specification Index

> **Purpose:** this directory is the **source of truth** for what the WeChat Moments app must do, how well it must do it, and how it is structured. Every planning, implementation, refactoring, and review task starts here.
>
> **Audience:** anyone — human or agent — about to change production code. See [`../CLAUDE.md`](../CLAUDE.md) → *Project Instructions* for the enforceable workflow.
>
> **Status:** the codebase is **intentionally partial**. These documents describe the *target*, not the current state. Where the shipped code does not yet satisfy a requirement, the requirement is marked **⛔ not met** with a pointer to the offending code. Those markers are the project's backlog.

---

## 1. Documents

| Document | Governs | Owns ID prefixes |
|----------|---------|------------------|
| [`functional-specification.md`](./functional-specification.md) | What the app does: screen anatomy, the mock API data contract, feed/pagination/tweet-rendering behaviour, out-of-scope items. | `FR-API-*`, `FR-HEADER-*`, `FR-FEED-*`, `FR-PAGE-*`, `FR-TWEET-*`, `FR-DATA-*` |
| [`non-functional-requirements.md`](./non-functional-requirements.md) | How well it does it: concurrency and performance, data resilience, layout adaptivity, testability. | `NFR-PERF-*`, `NFR-DATA-*`, `NFR-LAYOUT-*`, `NFR-TEST-*` |
| [`architecture-specification.md`](./architecture-specification.md) | How it is built: MVVM over Combine, layer responsibilities, dependency flow, folder layout, naming, testing structure. | `FAD-ARCH-*` |

All three carry `FAD-*` entries (see §3).

## 2. Normative language

**MUST** = mandatory · **SHOULD** = strongly recommended · **MAY** = optional.

These are used in the exact RFC-2119 sense. A **MUST** that the code does not satisfy is a defect, not a preference.

## 3. ID conventions

| Prefix | Meaning |
|--------|---------|
| `FR-<AREA>-NNN` | Functional requirement. Stable — never renumbered, only deprecated. |
| `NFR-<AREA>-NNN` | Non-functional requirement. Stable. |
| `FAD-<AREA>-<letter>` | **Future Architecture Decision** — a question deliberately left open. Recorded rather than guessed. |
| ⚠️ | Marks a contentious or blocking open item. |
| ✅ | Marks a **resolved** FAD, promoted into its own numbered subsection with a ratification date. This is the project's ADR mechanism. |
| ⛔ | Marks a requirement the current code does **not** satisfy. |

Cross-references are written inline and are expected to resolve: `fn-spec §3.2`, `FR-PAGE-002`, `NFR-PERF-004`, `arch-spec §7`, `FAD-DATA-a`. Source-code comments use the same form.

## 4. How to add or change a requirement

1. Requirements are added **only on explicit request**. Implementation work never edits `spec/` as a side effect — see `CLAUDE.md` → *Specification Preservation*.
2. New requirements get the **next free number** in their area. Numbers are never reused.
3. A requirement that becomes wrong is marked **deprecated** in place, with the reason and the replacing ID. It is not deleted.
4. Resolving a `FAD-*` means writing a new `### N.M Resolved: <title> (\`FAD-X-y\`) ✅` subsection carrying the decision, the ratification date, the rationale, and the assumptions carried forward — then updating the consolidated open-questions table at the foot of that document.

## 5. Deliberate divergences from the reference project

This structure is adapted from the sibling `AlineaTake-Home` take-home. Three of its documents/areas are **intentionally absent**:

- **No `design-specification.md`.** There is no Figma source for this exercise. Visual truth is the three reference screenshots in the root [`README.md`](../README.md); layout values that were inferred from them are tagged `[I]`/`[A]` in `fn-spec §2` and `§5` rather than given a document of their own.
- **No design-system specification.** The app is a single static screen; a token/component two-tier system is not proportional to that scope (see `arch-spec §1`).
- **No localization, theming, or VoiceOver NFR areas.** The exercise brief does not ask for them. `NFR-LAYOUT` covers the one presentation requirement the brief *does* state — support for all device sizes and orientations.

The scope guard is deliberate: this specification set covers only what the exercise asks for, plus the correctness and testability required to deliver it.

---

*This document is an index and a convention register. It defines no product behaviour and affects no production code.*
