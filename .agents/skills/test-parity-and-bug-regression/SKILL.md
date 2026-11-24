---
name: test-parity-and-bug-regression
description: >-
  Add or expand deterministic unit, persistence/security, state-concurrency, and responsive UI
  widget/E2E tests (360x800 compact mobile, 1.5x-2.0x text scaling, reduced motion, Light/Dark
  themes, 1280x840 desktop), diagnose layout overflows or flaky async tests, and lock bug fixes
  with regression coverage. Use whenever implementing features, fixing bugs, or auditing test gaps.
---

# Test Parity & Bug Regression Runbook

Use this skill to guarantee every new feature, UI refactor, or bug fix ships with fast, deterministic, high-signal automated test coverage.

---

## Step 1 — Map Coverage Across the 4-Layer Pyramid

For every change, verify coverage at the appropriate layer(s):
1. **Domain / Engine Unit Tests**: Pure logic, math precision, edge cases (`0`, negative, rounding, invalid input), and architectural import boundary tests.
2. **Database / Security Tests**: Encryption at rest, wrong-key rejection, schema constraints, composite foreign keys, triggers, immutability, atomic rollback.
3. **State / Integration Tests**: Async race cancellation (stale responses discarded after rapid switch), error/retry recovery, multi-step end-to-end flows.
4. **UI, Responsive & Accessibility Tests**: Interactive user flows, filters, sort menus, custom dialogs (`ModernDialogShell`), empty/reset states, and zero exceptions across:
   - Compact mobile (`360x800`)
   - Standard mobile (`390x844`)
   - Large text scale (`1.5x` and `2.0x`) + reduced motion (`disableAnimations: true`)
   - Light & Dark themes
   - Wide desktop (`1280x840`)

---

## Step 2 — Enforce Strict Bug-Fix Regression Discipline

When fixing a bug (overflow, crash, wrong calculation, race condition):
1. **Reproduce First**: Confirm the exact failure condition (e.g., `RenderFlex overflowed by 38 pixels` in `PopupMenuItem` at `390x844` or `360x800`).
2. **Fix the Real Root Cause**: Never weaken assertions, skip tests, or silence `tester.takeException()`.
3. **Lock With a Test**: Ensure an automated test taps the exact control/popup/edge case and asserts `expect(tester.takeException(), isNull)` so the regression cannot return.

---

## Step 3 — Keep Tests Fast & 100% Deterministic

- Inject fake/deterministic clocks (`FixedUtcClock`), in-memory databases, and in-memory keystores.
- Add semantic `Key('feature_control_action')` locators for icon buttons, segmented controls, and dialog confirm actions.
- Reset surface sizes (`addTearDown(() => tester.binding.setSurfaceSize(null))`), close DB connections, and reset DI containers (`getIt.reset()`) in `tearDown`.
- After async repository writes inside widget tests, yield briefly inside `tester.runAsync(...)` followed by `await tester.pump(); await tester.pumpAndSettle();` when waiting on real async SQLite streams.

---

## Step 4 — Execute Full Suite & Gate

Run the complete test suite (`flutter test` / `npm test` / `pytest` / `go test -race ./...` / `cargo test`) after the final edit, confirm **100% passing with 0 skipped regressions**, and pair with `full-stack-verify-and-visual-qa` before reporting completion.
