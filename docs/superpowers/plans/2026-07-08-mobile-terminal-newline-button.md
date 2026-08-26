# Mobile Terminal Newline Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a compact `↵` button to the Mobile terminal input bar that inserts a literal newline into the prompt text without sending input.

**Architecture:** The current repository only contains Mobile documentation placeholders, so this plan first records the product requirement and acceptance contract. When the KMP + Compose UI exists, the feature should live in the terminal input composable and update local text-field state by inserting `\n` at the current selection.

**Tech Stack:** KMP + Compose Multiplatform planned for Mobile UI; Markdown docs for current repository state.

---

### Task 1: Record Product Requirement

**Files:**
- Create: `docs/requirements/2026-07-08-mobile-terminal-newline-button.md`

- [x] **Step 1: Write requirement doc**

Record background, goals, platform needs, flow, non-goals, and unresolved questions for a `↵` newline button.

- [x] **Step 2: Verify requirement file exists**

Run: `test -f docs/requirements/2026-07-08-mobile-terminal-newline-button.md`

Expected: exit code `0`.

### Task 2: Record Manual Acceptance

**Files:**
- Create: `docs/acceptance/mobile-terminal-newline-button.md`

- [x] **Step 1: Write acceptance scenarios**

Cover empty input, end insertion, middle insertion, keyboard focus retention, and narrow-screen usability.

- [x] **Step 2: Verify acceptance file exists**

Run: `test -f docs/acceptance/mobile-terminal-newline-button.md`

Expected: exit code `0`.

### Task 3: Update Mobile README

**Files:**
- Modify: `MobileClient/README.md`

- [x] **Step 1: Add terminal input requirement reference**

Add the `↵` newline button to the current Mobile goals and reference the requirement and acceptance docs.

- [x] **Step 2: Verify README mentions `↵`**

Run: `rg -n "↵|newline|换行" MobileClient/README.md`

Expected: output includes the terminal input requirement.

### Task 4: Record Development Memory

**Files:**
- Create: `docs/memory/features/2026-07-08-mobile-terminal-newline-button.md`

- [x] **Step 1: Write memory note**

Record why the feature is documented rather than implemented in UI source today, plus the agreed label `↵`.

- [x] **Step 2: Verify memory file exists**

Run: `test -f docs/memory/features/2026-07-08-mobile-terminal-newline-button.md`

Expected: exit code `0`.
