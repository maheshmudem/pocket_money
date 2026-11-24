---
name: modern-ui-redesign-and-component-kit
description: >-
  Audit screens, popups, modals, and themes for dated UI, oversized layouts, text clipping, or
  Light/Dark mismatch; extract reusable custom UI primitives (accent cards, status pills,
  hairline action bars, modern frosted dialogs); and verify before/after parity across breakpoints.
  Use when redesigning a screen, overhauling popups/dialogs, or unifying visual design across an app.
---

# Modern UI Redesign & Reusable Component Kit Runbook

Follow this structured playbook whenever overhauling a screen, replacing legacy popups, or elevating an app's visual craft.

---

## Step 1 — Visual & Code Audit (Before Editing)

1. **Capture "Before" Evidence**: On live emulator/device or browser, screenshot the current screen and popups so layout bloat, clipped text, and spacing issues are concrete.
2. **Audit Legacy Patterns Across the Codebase**:
   - Search for raw stock popups (`AlertDialog`, `SimpleDialog`, `showDialog`), bulky `Card`/`ListTile` boilerplate, heavy full-bleed gradients clashing with Light Mode, or awkward multi-row `FilterChip`/`ChoiceChip` strips.
   - Check `test/` for existing text/key/type locators (`find.text`, `Key(...)`, `find.byType`) that must be preserved or intentionally updated.
3. **Check Design Tokens First**: Inspect theme extensions and typography tokens (`app_tokens.dart`, `app_theme.dart`, CSS variables, Tailwind config) so new components inherit 100% theme-native colors automatically.

---

## Step 2 — Build or Reuse Shared Custom Primitives First

Before editing individual screens, ensure shared reusable primitives exist in `shared/widgets/` (or `components/ui/`):
- **Elevated Accent Card** (`FintechAccentCard`): Theme-native elevated surface, `1px` crisp hairline border, `3px` customizable top gradient trim, subtle ambient corner glow, optional hairline-divided `bottomBar`.
- **Compact Status Pill** (`FintechStatusPill`): Stadium badge with optional colored dot or `12px` icon.
- **Hairline Action Strip** (`FintechFlatActionBar`): Edge-to-edge equal-width interactive actions separated by thin vertical hairlines (`Spend | Receive | Transfer | Vault`).
- **Modern Animated Custom Dialog** (`ModernDialogShell` / `showModernDialog` / `showModernConfirmDialog`):
  - Spring-scale + fade transition with subtle frosted backdrop dim and automatic reduced-motion fallback.
  - `3px` semantic top trim (`brand` / `success` / `warning` / `danger`), `IconSquircle` header + bold title + concise subtitle + circular close (`×`) button.
  - Keyboard-safe scrollable body (`viewInsets.bottom`), live preview widgets where helpful (live avatar preview, passphrase strength bar), hairline footer divider, and rounded full-height `Cancel` + primary/destructive action buttons.

---

## Step 3 — Compact, Zero-Waste Screen Overhaul

Apply these upgrades to every segment of the target screen:
1. **Reclaim Above-the-Fold Space**:
   - Replace verbose 2-line headers + oversized hero cards with compact single-row headers and crisp elevated hero cards.
   - Merge closely related KPI cards into a single 2- or 3-column inline tonal strip with `1px` vertical dividers.
   - Replace multi-row wrapped filter chips with a pill search input + single-row animated sliding segmented control + compact sort/more/archive circular buttons.
2. **Zero Truncation & Zero Overflow**:
   - Wrap dynamic `Row` / `PopupMenuItem` labels in `Flexible` / `Expanded` (`maxLines: 1`, `TextOverflow.ellipsis`).
   - Wrap right-aligned monetary values in `ConstrainedBox + FittedBox(fit: BoxFit.scaleDown)`.
   - Place percentage readouts (`95%`) in a dedicated tabular text beside progress bars instead of appending them to subtitles.
   - Remove duplicate subtitles (e.g., showing category again when identical to the row title).
3. **Performance & Motion Polish**:
   - Wrap heavy charts & custom painters in `RepaintBoundary`.
   - Use sliver/custom scroll views with `ScrollCacheExtent.pixels(640)` and elastic scroll physics.
   - Add crisp tactile haptics (`HapticFeedback.selectionClick()`) on interactive taps.

---

## Step 4 — Verify & Inspect Both Themes

1. Update and expand automated tests covering the redesigned controls, dialogs, empty states, `360x800`, `1.5x–2.0x` text scale, and `1280x840` desktop.
2. Activate the `full-stack-verify-and-visual-qa` skill to run the full post-edit quality gate and visually compare live Daylight Light & Obsidian Dark screenshots before reporting completion.
