---
name: learn-and-persist-workflow
description: >-
  Capture hard-won bug root causes, user preferences, coding/UI conventions, and tooling tricks
  into concise, deduplicated workspace rules (.agents/rules/learned-lessons.md) or sync the
  portable AGENTS.md + .agents/ kit to another repository or global ~/.gemini/config/.
  Use when the user runs /learn, asks to remember a preference/workflow, or after solving a
  non-obvious technical or UI issue.
---

# Continuous Learning & Workflow Persistence Runbook (`/learn`)

Use this skill to convert real engineering experience and user feedback into durable, low-token-overhead instructions that improve every future session and project.

---

## Step 1 — Distill the Signal

Identify what is worth persisting permanently:
- **User Preferences**: Repeated visual, structural, or workflow preferences (e.g., compact theme-native hero cards, zero raw `AlertDialog`, mandatory post-edit format/analyze/test/build + Light/Dark visual QA).
- **Root-Cause Gotchas**: Non-obvious bugs or framework traps that took investigation to solve (e.g., `TextTheme` overriding semantic colors, `PopupMenuItem` 256dp overflow, Windows PowerShell PNG pipe corruption, Flutter 3.41 `ScrollCacheExtent`).
- **Repeatable Time-Savers**: Exact commands or patterns that speed up future QA (e.g., `adb shell cmd uimode night yes/no`, safe `adb install -r`).

Do **NOT** record temporary one-off task notes, transient file line numbers, or generic language basics the model already knows.

---

## Step 2 — Persist Cleanly & Deduplicate

1. Read `.agents/rules/learned-lessons.md` first to avoid duplicate entries.
2. Add or refine a crisp bullet in **Trap -> Rule** format (2–4 lines max).
3. If a lesson represents a core workflow or UI principle rather than a specific gotcha, update the relevant numbered rule (`01-engineering-workflow.md`, `02-ui-ux-craft-standards.md`, `03-coding-architecture-security.md`, or `04-testing-automation-standards.md`) instead.
4. Keep every rule file well below the `24 KB` Antigravity per-file cap (aim for `< 10 KB` per file).

---

## Step 3 — Sync Across Projects or Globally (When Requested)

Use the bundled PowerShell helper [sync_agents_kit.ps1](./scripts/sync_agents_kit.ps1):

- **Copy the entire `AGENTS.md` + `.agents/` kit to another project**:
  ```powershell
  .\.agents\skills\learn-and-persist-workflow\scripts\sync_agents_kit.ps1 -TargetRepo "C:\path\to\other-project"
  ```
- **Install all skills globally into `~/.gemini/config/skills/` (available in EVERY project on this PC)**:
  ```powershell
  .\.agents\skills\learn-and-persist-workflow\scripts\sync_agents_kit.ps1 -InstallGlobal
  ```
- **Preview without writing (`-DryRun`)**:
  ```powershell
  .\.agents\skills\learn-and-persist-workflow\scripts\sync_agents_kit.ps1 -InstallGlobal -DryRun
  ```
