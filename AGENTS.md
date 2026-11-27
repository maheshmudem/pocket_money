# Engineering & Quality Operating Standard (`AGENTS.md`)

This repository enforces a **Production-Grade Engineering, Clean Architecture, Modern UI Craft, Automated Test Parity, Live Visual QA, and Continuous Learning (`/learn`)** standard. Every agent and contributor MUST follow these directives on every task.

---

## 1. Core Engineering & Architecture Discipline

1. **Inspect Before Editing**: Read relevant source files, design tokens, domain entities, and existing tests before changing code. Never guess APIs, field names, or test locators.
2. **Reuse & Modularize**: Extract repeated UI surfaces, cards, dialogs, status badges, action bars, formatters, and helpers into shared modules (`lib/shared/` or `src/shared/`). Never copy-paste boilerplate across screens.
3. **Preserve Layer Boundaries & Precision**: Keep pure domain/business/financial engines 100% decoupled from UI, database, and platform SDKs. Use integer minor units or decimals for currency (never floats), UTC timestamps, atomic transactions, and typed errors (`Result`).
4. **Concurrency, Lifecycle & Security**: Dispose all controllers/streams, guard `mounted` after every `await`, discard stale async responses on rapid context switches, never hardcode secrets, and redact PII/credentials from logs.
5. **No Half-Finished States**: Never claim completion with failing tests, analyzer warnings/infos, unformatted code, or unverified UI regressions.

---

## 2. Modern UI/UX & Accessibility Discipline

- **Theme-Native Light & Dark Parity**: Every screen, card, chart, badge, modal, and empty state must look cohesive and high-contrast (WCAG AA+) in both Daylight Light and Obsidian Dark themes. Prefer elevated theme-native surfaces with a uniform `1px` hairline border and soft ambient glow over heavy hardcoded gradient slabs or top-only border strips.
- **Zero-Waste Compact Layouts**: Prioritize scannable hierarchy, crisp `1px` hairline dividers, tabular figures (`FontFeature.tabularFigures()`) for all numbers/currencies/percentages, and generous above-the-fold utility.
- **Zero Legacy Popups**: Never use raw stock `AlertDialog` boxes for user-facing flows. Always use the reusable animated custom dialog shell (`showModernDialog`, `ModernDialogShell`, `showModernConfirmDialog`) with header icon squircle, uniform `1px` hairline border + soft ambient glow, frosted backdrop, keyboard-safe scrolling, and balanced rounded actions.
- **Overflow & Truncation Proofing**:
  - Wrap dynamic `Row` / `PopupMenuItem` labels in `Flexible` / `Expanded` (`maxLines: 1`, `TextOverflow.ellipsis`).
  - Wrap right-aligned monetary values in `ConstrainedBox` + `FittedBox(fit: BoxFit.scaleDown)`.
  - Place `%` readouts cleanly beside progress bars rather than cramming them into truncated subtitles.
- **60/120fps Motion & A11y**: Respect reduced-motion settings, pair semantic colors with icons/labels (never color alone), wrap heavy charts/gauges in `RepaintBoundary`, and use modern scroll cache APIs (`ScrollCacheExtent.pixels(640)` on Flutter 3.41+).

---

## 3. Automated Test Parity & Mandatory Post-Final-Edit Quality Gate

- **Test Parity**: Every new feature, interactive control, dialog, or bug fix MUST add or update automated tests covering the happy path, edge cases, and responsive matrix (`360x800` compact mobile, `1.5x–2.0x` large text scale + reduced motion, Light/Dark themes, `1280x840` desktop) with zero layout exceptions.
- **Mandatory Post-Final-Edit Pipeline** (re-run from step 1 if ANY edit is made after a failure):

### Flutter / Dart (Default in this Repo)
```powershell
.\.agents\skills\full-stack-verify-and-visual-qa\scripts\verify_flutter.ps1
```
*(Executes `dart format` + strict diff check -> `flutter analyze --fatal-infos` -> `flutter test` -> universal multi-ABI APK build `android-arm,android-arm64,android-x64`.)*

### Other Tech Stacks (Portable Equivalents)
- **TypeScript / React / Next.js**: `npm run format:check && npm run lint && npm run typecheck && npm test && npm run build`
- **Python / FastAPI**: `ruff format --check . && ruff check . && mypy . && pytest`
- **Go**: `gofmt -l . && go vet ./... && go test -race ./... && go build ./...`
- **Rust**: `cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test && cargo build`

---

## 4. Live Visual & Runtime QA (For Any UI Change)

1. **Install Without Wiping Data**: Use `adb -s <serial> install -r <apk>` — **NEVER** run `adb shell pm clear` unless explicitly instructed.
2. **Inspect Both Themes Visually**: Capture real screenshots in **both Light and Dark mode** (toggle cleanly via `adb shell cmd uimode night yes` / `no`, pull binary PNGs via `/sdcard/` + `adb pull` on Windows) and inspect every screenshot for spacing, alignment, clipping, contrast, and polish.
3. **Audit Runtime Logs**: Confirm zero runtime errors (`adb -s <serial> logcat -d -t 50 flutter:* AndroidRuntime:E *:S` or browser/server console) and restore default theme/state when done.

---

## 5. Continuous Learning (`/learn`), Safety & Playbooks

- **Persist Hard-Won Lessons**: When corrected by the user or after solving a non-obvious framework/UI/tooling trap, record a concise **Trap -> Rule** entry in `.agents/rules/learned-lessons.md` (or use the `/learn` command / `learn-and-persist-workflow` skill).
- **Strict Honesty**: Report only verified post-final-edit test counts, build outputs, and visual checks. Never fabricate results or run destructive git/DB/device wipes without explicit approval.
- **Included Workspace Rules**:
  - `.agents/rules/01-engineering-workflow.md` — 7-stage lifecycle & multi-stack gates
  - `.agents/rules/02-ui-ux-craft-standards.md` — Modern UI/UX & reusable component system
  - `.agents/rules/03-coding-architecture-security.md` — Clean architecture, precision, concurrency & security
  - `.agents/rules/04-testing-automation-standards.md` — 4-layer testing pyramid & regression discipline
  - `.agents/rules/05-continuous-learning.md` & `.agents/rules/learned-lessons.md` — `/learn` protocol & battle-tested gotchas
- **Included On-Demand Skills**:
  - `full-stack-verify-and-visual-qa` — Quality gate script, emulator Light/Dark visual QA & `logcat` audit
  - `modern-ui-redesign-and-component-kit` — Screen/dialog overhaul & shared primitive design
  - `test-parity-and-bug-regression` — Deterministic unit/E2E/responsive testing & bug-fix regression locking
  - `learn-and-persist-workflow` — `/learn` persistence & 1-command multi-repo / global kit sync
