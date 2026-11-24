---
name: full-stack-verify-and-visual-qa
description: >-
  Run the full post-edit automated engineering quality gate (format check, strict static analysis,
  full unit/widget/integration tests, universal build) plus live emulator/device Daylight Light &
  Obsidian Dark visual screenshot inspection and runtime logcat audit. Use after any code, UI,
  dialog, theme, or feature change before reporting completion.
---

# Full-Stack Verification & Live Visual QA Runbook

Follow this runbook after the **final code edit** of every feature, bug fix, or UI redesign to guarantee zero regressions, zero analyzer warnings, passing tests, valid builds, and visually verified Light & Dark UI.

---

## Step 1 — Run the Automated Quality Gate

### Flutter / Dart (Windows PowerShell)
Run the bundled fail-fast script:
```powershell
.\.agents\skills\full-stack-verify-and-visual-qa\scripts\verify_flutter.ps1
```
Or run each gate explicitly:
```powershell
dart format lib test
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test
flutter build apk --debug --target-platform android-arm,android-arm64,android-x64
```

### Non-Flutter Projects
Run the exact stack equivalent before proceeding:
- **TypeScript / Web**: `npm run format:check && npm run lint && npm run typecheck && npm test && npm run build`
- **Python**: `ruff format --check . && ruff check . && mypy . && pytest`
- **Go**: `gofmt -l . && go vet ./... && go test -race ./... && go build ./...`
- **Rust**: `cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test && cargo build`

**Hard Rule**: If ANY step fails and you edit code to fix it, **re-run all steps from the beginning** so every reported result is strictly post-final-edit.

---

## Step 2 — Check Test Parity & Coverage Gaps

Before moving to live device QA, confirm:
1. Every newly added interactive control, filter, sort order, dialog, or route is exercised by an automated test.
2. Responsive & accessibility tests cover compact mobile (`360x800`), large text scale (`1.5x` / `2.0x`), reduced motion, Dark Mode, and desktop (`1280x840`) with `expect(tester.takeException(), isNull)`.
3. Zero legacy `AlertDialog` widgets were accidentally introduced where `ModernDialogShell` / `showModernDialog` belongs.

---

## Step 3 — Live Device / Emulator Visual QA (Light + Dark)

For mobile/Flutter UI changes with a connected Android emulator or device (`adb devices`):

1. **Install Safely (Preserve Existing User Data)**:
   ```powershell
   adb -s <serial> install -r build\app\outputs\flutter-apk\app-debug.apk
   ```
   > **NEVER** run `adb shell pm clear` on user or test devices unless explicitly requested.

2. **Launch Cleanly**:
   ```powershell
   adb -s <serial> shell am force-stop <applicationId>
   adb -s <serial> shell am start -n <applicationId>/.MainActivity
   ```
   Allow cold-start splash to finish (`~4–6s` on debug emulators).

3. **Capture Light Mode Screenshots (Windows-Safe Binary Pull)**:
   ```powershell
   adb -s <serial> shell screencap -p /sdcard/qa_light.png
   adb -s <serial> pull /sdcard/qa_light.png "<artifact_dir>\qa_light.png"
   ```
   > Always capture via `/sdcard/` + `adb pull` on Windows PowerShell; never redirect binary `exec-out` with `>`.

4. **Toggle System Dark Mode & Capture Dark Mode Screenshots**:
   ```powershell
   adb -s <serial> shell cmd uimode night yes
   Start-Sleep -Milliseconds 1200
   adb -s <serial> shell screencap -p /sdcard/qa_dark.png
   adb -s <serial> pull /sdcard/qa_dark.png "<artifact_dir>\qa_dark.png"
   ```
   Restore Light / default mode when done:
   ```powershell
   adb -s <serial> shell cmd uimode night no
   ```

5. **Visually Inspect Every Captured Screenshot**:
   Open every PNG with `read_file` and actively check for:
   - Text clipping or unwanted ellipsis (`"95% sh..."`, truncated labels, clipped buttons)
   - Horizontal or vertical overflow stripes
   - Excessive blank whitespace or bloated cards pushing core content below the fold
   - Contrast readability in BOTH Daylight Light and Obsidian Dark modes
   - Alignment of dividers, icons, badges, modals, and keyboard insets

6. **Audit Runtime Logs**:
   ```powershell
   adb -s <serial> logcat -d -t 50 flutter:* AndroidRuntime:E *:S
   ```
   Confirm **zero** uncaught Flutter exceptions, rendering overflows, or Android runtime crashes.

---

## Step 4 — Security & Hygiene Sanity Check

- Confirm `git status` contains only intended project files (no stray temp PNGs, scratch scripts, or leaked `.env` / secrets).
- Confirm no hardcoded tokens, passphrases, or unredacted PII were added to source code or logs.
- Report exact post-final-edit verification outcomes concisely with clickable file paths.
