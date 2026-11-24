# Portable AI Engineering, Testing, UI & `/learn` Workflow Kit

This `.agents/` directory + root [AGENTS.md](../AGENTS.md) packages a complete, battle-tested **Engineering, Coding, Security, Modern UI Craft, Automated Testing, Visual QA, and Continuous Learning (`/learn`)** system in the official Antigravity & multi-agent discovery format.

---

## Complete Kit Map

### Always-On & Modular Rules
| File | Covers |
|---|---|
| [AGENTS.md](../AGENTS.md) | Root project operating standard (auto-loaded by Antigravity, Codex, Cursor, Gemini CLI) |
| [rules/01-engineering-workflow.md](./rules/01-engineering-workflow.md) | 7-phase delivery lifecycle, multi-stack quality gate matrix (Flutter, TS, Python, Node, Kotlin, Go, Rust), and device/tooling safety guardrails |
| [rules/02-ui-ux-craft-standards.md](./rules/02-ui-ux-craft-standards.md) | Theme-native Light & Dark design system, reusable component kit (`FintechAccentCard`, `FintechStatusPill`, `FintechFlatActionBar`, `ModernDialogShell`), overflow-proofing, and 60/120fps motion |
| [rules/03-coding-architecture-security.md](./rules/03-coding-architecture-security.md) | Clean architecture layer boundaries, zero-float money precision, atomic DB writes, async mount/race guards, encryption, and redacted logging |
| [rules/04-testing-automation-standards.md](./rules/04-testing-automation-standards.md) | 4-layer testing pyramid, mandatory test parity, bug-fix regression locking, responsive/a11y viewport matrix (`360x800`, `1.5x–2.0x`, `1280x840`), and zero-flakiness hygiene |
| [rules/05-continuous-learning.md](./rules/05-continuous-learning.md) | `/learn` protocol for turning user feedback & solved pitfalls into durable low-token rules |
| [rules/learned-lessons.md](./rules/learned-lessons.md) | 12 pre-seeded battle-tested lessons (Flutter 3.41 `ScrollCacheExtent`, `TextTheme` color override, `SweepGradient` cap bleed, `PopupMenuItem` overflow, Windows PNG pull, instant `uimode night`, safe `adb install -r`) |

### On-Demand Reusable Skills & Helper Scripts
| Skill | Purpose | Bundled Script |
|---|---|---|
| [full-stack-verify-and-visual-qa](./skills/full-stack-verify-and-visual-qa/SKILL.md) | Format, strict static analysis, full test suite, universal multi-ABI build, live Light & Dark screenshot QA, and `logcat` audit | [verify_flutter.ps1](./skills/full-stack-verify-and-visual-qa/scripts/verify_flutter.ps1) |
| [modern-ui-redesign-and-component-kit](./skills/modern-ui-redesign-and-component-kit/SKILL.md) | Audit dated UI / legacy `AlertDialog`s, build shared UI primitives, reclaim screen space, and verify Light/Dark cohesion | — |
| [test-parity-and-bug-regression](./skills/test-parity-and-bug-regression/SKILL.md) | Design 4-layer tests, reproduce & lock bug fixes with regression coverage, and eliminate test flakiness | — |
| [learn-and-persist-workflow](./skills/learn-and-persist-workflow/SKILL.md) | Persist `/learn` lessons cleanly without bloating context and sync the entire kit across projects or globally | [sync_agents_kit.ps1](./skills/learn-and-persist-workflow/scripts/sync_agents_kit.ps1) |

---

## 1-Command Reuse Across Other Projects or Globally

### 1. Copy the Entire Kit Into Any New Project (Recommended for Git / Teams)
```powershell
.\.agents\skills\learn-and-persist-workflow\scripts\sync_agents_kit.ps1 -TargetRepo "C:\path\to\new-project"
```

### 2. Install All 4 Skills Globally on Your PC (`~/.gemini/config/skills/`)
Makes all 4 skills automatically available in **every** workspace you open on this computer:
```powershell
.\.agents\skills\learn-and-persist-workflow\scripts\sync_agents_kit.ps1 -InstallGlobal
```
*(Add `-DryRun` anytime to preview what will be copied without modifying disk.)*

### 3. Run the Full Flutter Quality Gate Anytime
```powershell
# Full gate: Format -> Analyze (--fatal-infos) -> Tests -> Multi-ABI APK
.\.agents\skills\full-stack-verify-and-visual-qa\scripts\verify_flutter.ps1

# Full gate + safe in-place install on emulator (preserves existing data)
.\.agents\skills\full-stack-verify-and-visual-qa\scripts\verify_flutter.ps1 -InstallDevice emulator-5554

# Fast check without APK build
.\.agents\skills\full-stack-verify-and-visual-qa\scripts\verify_flutter.ps1 -SkipBuild
```

### 4. Use `/learn` Anytime
Whenever you refine a preference or solve a tricky setup/bug in chat, type `/learn` (or ask the agent to update `learned-lessons.md`) to permanently add that rule and keep future sessions even sharper.
