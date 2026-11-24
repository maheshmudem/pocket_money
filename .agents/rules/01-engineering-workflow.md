# Portable Engineering Workflow & Verification Rules

Use this rulebook across any software project to maintain repeatable, zero-regression engineering quality from initial research through live verification.

---

## 1. End-to-End Task Execution Lifecycle

Execute every non-trivial feature, refactor, or UI overhaul in 7 disciplined phases:

1. **Discover & Audit**
   - Read target files, shared theme/design tokens, domain models, and existing tests.
   - Grep for existing test locators (`find.text`, `Key(...)`, `find.byType`, ARIA labels, test IDs) so upgrades maintain or intentionally evolve test coverage cleanly.
   - Check git status and active devices/runtimes before modifying files.
2. **Design for Reuse & Cohesion**
   - Identify repeated visual patterns (cards, badges, filters, dialogs, sheets, empty states) and promote them to shared custom components instead of duplicating widgets per page.
   - Confirm architecture layer rules (pure domain/business logic stays free of UI/framework/DB imports).
3. **Implement Cleanly**
   - Keep code idiomatic, strongly typed, null-safe, and free of deprecated framework APIs (e.g., use `ScrollCacheExtent.pixels(640)` instead of deprecated `cacheExtent` on Flutter 3.41+).
   - Add defensive layout constraints (`Flexible`, `Expanded`, `ConstrainedBox + FittedBox`, `maxLines`, `TextOverflow.ellipsis`) from the start so narrow viewports and large font scales never overflow.
   - Ensure keyboard-safe scrolling (`MediaQuery.viewInsetsOf(context).bottom` / `SingleChildScrollView`) on every dialog, modal, and form.
4. **Update & Expand Automated Tests**
   - Add assertions for every new interactive control, filter, sort order, dialog, empty/reset state, and error path.
   - Verify responsive & accessibility matrices where applicable: compact mobile (`360x800`), standard mobile (`390x844`), large text scaling (`1.5x` & `2.0x`), reduced motion, Dark Mode, and desktop (`1280x840`).
5. **Run Full Automated Quality Gate (Post-Final-Edit)**
   - Format -> Verify zero format diff -> Strict static analysis / lint (zero warnings/infos) -> Full automated test suite -> Universal target build.
   - If ANY edit is made to fix a lint or test failure, **re-run the full gate from the start**.
6. **Perform Live Visual & Runtime QA**
   - Install/launch on a live emulator, device, or browser.
   - Visually inspect every modified screen/dialog in **both Light and Dark modes** via real screenshots.
   - Inspect runtime logs (`logcat`, browser console, server logs) and confirm zero uncaught exceptions or rendering assertions.
7. **Summarize & Document**
   - Record key modified files with clickable paths, exact verified gate results, and visual evidence (screenshots/walkthroughs) without overstating unverified work.

---

## 2. Multi-Stack Quality Gate Reference

When copying `.agents/` into another repository, run the matching strict pipeline for that stack:

| Stack | Format Check | Lint / Static Analysis | Automated Tests | Build Verification |
|---|---|---|---|---|
| **Flutter / Dart** | `dart format --output=none --set-exit-if-changed lib test` | `flutter analyze --fatal-infos` | `flutter test` | `flutter build apk --debug --target-platform android-arm,android-arm64,android-x64` |
| **TypeScript / Web** | `npx prettier --check .` | `npm run lint && npx tsc --noEmit` | `npm test` (unit + E2E) | `npm run build` |
| **Python** | `ruff format --check .` | `ruff check . && mypy .` | `pytest -q` | Package / Docker build |
| **Node / Backend API** | `npm run format:check` | `npm run lint && npm run typecheck` | `npm test` (unit + integration) | `npm run build` |
| **Android (Kotlin)** | `./gradlew ktlintCheck` | `./gradlew lint` | `./gradlew testDebugUnitTest` | `./gradlew assembleDebug` |
| **Go** | `gofmt -l .` | `go vet ./... && golangci-lint run` | `go test -race ./...` | `go build ./...` |
| **Rust** | `cargo fmt --check` | `cargo clippy --all-targets -- -D warnings` | `cargo test` | `cargo build` |

---

## 3. High-Value Safety Guardrails (Lessons Learned)

- **Preserve User & Test Data on Devices**: Always use `adb install -r` (in-place upgrade). **Never** execute `adb shell pm clear` or wipe local databases on connected emulators/phones unless the user explicitly asks for a factory reset.
- **Safe Windows Binary Screenshot Capture**: Never shell-redirect binary `adb exec-out screencap` in Windows PowerShell (`>` corrupts binary streams). Always write to `/sdcard/tmp.png` and retrieve with `adb pull`.
- **Clean Device Reset After QA**: When toggling system dark mode or navigating during visual QA, restore the emulator/device to its default theme (`Auto` / `uimode night no`) and clean screen before finishing.
- **No Sensitive Leakage**: Never hardcode credentials, encryption keys, or tokens in code, tests, or logs; redact sensitive fields in diagnostic logs.
- **No Unnecessary Workspace Clutter**: Keep temporary scripts or diagnostic files out of the repo root (use scratch dirs or clean up temp artifacts before finishing).
- **Zero Flaky Waits**: When interacting with animated/elastic UIs (e.g., `BouncingScrollPhysics`), allow settle time before tapping scrolled elements, and use explicit deterministic waits in automated tests (`pumpAndSettle`, `waitForSelector`).
