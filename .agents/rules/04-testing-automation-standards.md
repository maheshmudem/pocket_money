# Automated Testing, Test Parity & Regression Standards

Every code change must ship with matching automated verification so bugs are caught in seconds by CI/tests instead of reaching users.

---

## 1. The 4-Layer Testing Pyramid

Maintain balanced, fast, deterministic coverage across all 4 layers:

1. **Pure Domain & Logic Unit Tests**
   - Verify core math, business rules, parsers, validators, formatters, and architectural layer boundaries (e.g., verifying `domain/` has zero UI/DB imports).
   - Cover edge cases explicitly: `0`, negative values, max/min precision, multi-currency minor units (`0`, `2`, `3`, `4` decimals), rounding, and invalid inputs.
2. **Persistence, Integrity & Security Tests**
   - Verify encryption at rest (ciphertext on disk, wrong-key rejection, valid-key decryption).
   - Verify database constraints, composite foreign keys, triggers, immutability rules, deduplication, and atomic rollback on failure.
3. **State Management & End-to-End Repository Tests**
   - Verify async race handling (e.g., stale response discarded after rapid profile/filter switch), error states, retry flows, and multi-step workflows (create -> update -> query -> filter -> reverse/delete -> backup/restore).
4. **UI, Responsive Layout & Accessibility Widget/E2E Tests**
   - Exercise every interactive user journey: navigation tabs, search, sort menus, sliding segmented filters, empty/reset states, custom dialogs (`ModernDialogShell`), modals/sheets, and live theme toggling.
   - Verify zero layout exceptions (`expect(tester.takeException(), isNull)`) across the full viewport & accessibility matrix:
     - **Compact Mobile**: `360x800`
     - **Standard Mobile**: `390x844`
     - **Large Accessibility Text Scale**: `1.5x` and `2.0x` + `disableAnimations: true` (reduced motion)
     - **Theme Parity**: Both Light and Dark modes
     - **Wide / Desktop**: `1280x840`

---

## 2. Mandatory Test Parity Rules

- **New Feature = New Assertions**: Never add a button, filter, sort order, dialog, form field, or empty state without adding automated test assertions that actually tap/interact with it and verify the resulting state.
- **Bug Fix = Regression Test First**: Whenever fixing a bug (overflow, crash, math error, race condition), add a test covering the exact reproduction scenario so the bug can never silently return.
- **Inspect Existing Locators Before UI Edits**: Before renaming labels, changing widget types (e.g., `AlertDialog` -> `ModernDialogShell`), or restructuring cards, grep `test/` for existing text/key/type finders so intentional changes update tests cleanly with zero broken assertions.
- **Stable Semantic Keys**: Assign clear, descriptive `Key('feature_element_action')` identifiers (e.g., `Key('accounts_sort_btn')`, `Key('confirm_logout_action')`) to icon-only controls, segmented bars, and critical actions so tests stay readable and resilient to copy polish.

---

## 3. Deterministic & Fast Test Hygiene

- **Zero Flakiness**:
  - Inject deterministic dependencies (`FixedUtcClock`, in-memory SQLite executor, in-memory secure keystore, fake network/biometric adapters).
  - Never depend on wall-clock time (`DateTime.now()`), live external internet calls, or random ordering in unit/widget tests.
- **Proper Teardown & Isolation**:
  - Close databases, reset service locators (`getIt.reset()`), clear surface size overrides (`addTearDown(() => tester.binding.setSurfaceSize(null))`), and unmount widget trees cleanly at the end of every test.
- **Never Cheat Tests**:
  - Never weaken assertions, skip failing tests, or swallow `tester.takeException()` to force a green run — always fix the real root cause in code or test setup.
