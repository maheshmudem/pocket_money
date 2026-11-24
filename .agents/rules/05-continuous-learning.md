# Continuous Learning & Knowledge Persistence (`/learn`)

Agents improve across sessions by turning real bug fixes, user feedback, design refinements, and environment discoveries into compact, reusable rules instead of repeating the same trial-and-error.

---

## 1. When to Capture a New Lesson

Record a concise lesson in `.agents/rules/learned-lessons.md` (or trigger the `learn-and-persist-workflow` skill / `/learn` slash command) whenever:
1. **The user corrects behavior, UI style, sizing, or workflow preferences** (e.g., preferring compact theme-native cards over heavy gradient slabs, banning stock `AlertDialog`s, keeping theme toggles inside Profile instead of the top AppBar).
2. **A subtle framework, OS, or tooling trap is solved** (e.g., Flutter deprecation under `--fatal-infos`, Windows PowerShell binary pipe corruption, `TextTheme` color precedence, `PopupMenuItem` width constraints).
3. **A reusable architectural or UI pattern proves high-leverage** across multiple screens (e.g., `FintechAccentCard`, `ModernDialogShell`, `FintechFlatActionBar`).
4. **A multi-step setup or QA trick saves recurring time** (e.g., `adb shell cmd uimode night yes/no` for instant emulator Dark Mode verification).

---

## 2. How to Write High-Signal Lessons

Every entry in `learned-lessons.md` MUST follow the **Symptom -> Root Cause -> Permanent Rule** pattern in 2–4 lines:
- **Specific & Actionable**: Name the exact API, command, constraint, or file pattern.
- **Zero Fluff & Deduplicated**: Merge updates into existing bullets rather than appending duplicates.
- **Stay Lean**: Keep each rule file well under `12 KB` (system cap is `24 KB` per file) so rules never crowd out task context.
- **Scope Correctly**:
  - Put **project-specific conventions** (package IDs, domain invariants, screen locators) in the workspace's `.agents/rules/learned-lessons.md`.
  - Promote **universal cross-project lessons** (Flutter/TS/Python/ADB/UI craft patterns) into the portable kit or `~/.gemini/config/` via `sync_agents_kit.ps1`.

---

## 3. `/learn` Workflow Integration

- Users can type `/learn` at any time after a correction or complex solve to persist that behavior permanently.
- Before closing out a major milestone or tricky debugging session, proactively check whether a newly discovered gotcha belongs in `.agents/rules/learned-lessons.md`.
