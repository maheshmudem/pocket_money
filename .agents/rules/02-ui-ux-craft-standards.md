# Modern UI/UX Craft & Reusable Component Standards

Apply these UI/UX engineering principles across every screen, card, chart, bottom sheet, and popup dialog so the application feels cohesive, crisp, fast, and flagship-grade in both Light and Dark themes.

---

## 1. Visual System & Theme Cohesion

- **Theme-Native Elevated Surfaces**:
  - Build hero cards and primary panels on semantic surface tokens (`surfaceElevated`, `surfaceTonal`, `divider`, `cardShadow`) rather than loud hardcoded full-bleed gradients that look jarring in Light Mode.
  - Use a uniform **`1px` hairline border** + soft top-right ambient radial sheen (`~5%` opacity in Light, `~15%` in Dark) + semantic `IconSquircle` across every primary tab (never top-only border strips).
- **Strict Light & Dark Mode Parity**:
  - Verify contrast (WCAG AA minimum: `4.5:1` for body text, `3:1` for large text/icons) in both Daylight Light and Obsidian Dark themes.
  - Pair every semantic color (income/emerald, expense/crimson, warning/amber, transfer/blue) with an explicit directional icon or label — never rely on color alone.
- **Tabular Numerals Everywhere**:
  - Apply `FontFeature.tabularFigures()` to all currencies, KPIs, counts, percentages, and balances so animated transitions and aligned columns never jitter horizontally.

---

## 2. Reusable Custom Component Kit First

Never hand-code one-off containers or dated stock popups. Centralize and reuse shared primitives:

1. **Accent Hero Cards (`FintechAccentCard`)**: Elevated card with optional ambient glow, uniform `1px` hairline border, semantic `IconSquircle`, and optional hairline-divided `bottomBar` (no top-only trim strips).
2. **Compact Status Pills (`FintechStatusPill`)**: Soft tinted stadium pill with optional semantic dot or `12px` icon.
3. **Hairline Action Strips (`FintechFlatActionBar`)**: Flat edge-to-edge action rows separated by subtle vertical hairlines (`Spend | Receive | Transfer | Vault`) — cleaner and far less boxy than rows of grey rounded rectangles.
4. **Modern Custom Popups (`ModernDialogShell` / `showModernDialog` / `showModernConfirmDialog`)**:
   - **Ban raw stock `AlertDialog`** for user-facing popups.
   - Use smooth spring-scale + fade entrance (`Curves.easeOutBack` / `Curves.easeOutCubic`) with subtle frosted `BackdropFilter` dim and automatic reduced-motion fallback.
   - Include: uniform `1px` hairline border + soft ambient glow (no top-only strips), semantic `IconSquircle` + bold title + concise subtitle + circular close (`×`) button, keyboard-safe scrollable body (`viewInsets.bottom`), live interactive previews where helpful (e.g., live avatar preview while typing a name, passphrase strength meter), hairline footer divider, and full-height rounded pill action buttons (`Cancel` + primary/destructive CTA with loading indicator).

---

## 3. Zero-Waste Layout & Overflow-Proofing Checklist

- **Reclaim Above-the-Fold Space**:
  - Consolidate related KPIs into tight 2- or 3-column inline split strips separated by `1px` vertical dividers inside a single tonal container rather than stacking multiple oversized cards.
  - Replace multi-row wrapped filter chip blocks with a compact pill search bar + single-row animated sliding segmented filter + compact overflow/sort icon buttons.
  - Group chronological list items (e.g., ledger entries, activity logs) into Apple Wallet-style grouped cards with indented hairline dividers and smart zero-duplication subtitles.
- **Eliminate Clipping & Truncation**:
  - Wrap `Row` and `PopupMenuItem` text children in `Flexible` / `Expanded` with `maxLines: 1` and `TextOverflow.ellipsis`.
  - Wrap right-aligned amounts in `ConstrainedBox(maxWidth: ...)` + `FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight)`.
  - Place progress percentages (`95%`) in a dedicated tabular readout beside the progress bar rather than cramming `"• 95% share"` into a subtitle that truncates to `"• 95% sh..."`.
  - Keep 3-chip quick preset rows on ONE balanced horizontal line (`Expanded` children) so a 3rd chip never orphans onto row 2.
- **Audit Every Hidden Surface**:
  - Don't stop at the main tabs — also polish empty states, error views, bottom sheets, profile switchers, confirmation popups, and settings/secondary sub-pages so no dated UI hides anywhere in the app.

---

## 4. Motion, Haptics & 60/120fps Performance

- **Reduced-Motion First**: Always resolve animation durations through a shared motion helper (`AppMotion.resolve`) that returns `Duration.zero` when system reduced-motion is enabled.
- **Paint Isolation**: Wrap charts (`BarChart`, `PieChart`), radial gauges, and custom painters in `RepaintBoundary` to prevent unnecessary frame repaints while scrolling.
- **Smooth Scrolling**: Use `CustomScrollView` / sliver lists with `ScrollCacheExtent.pixels(640)` and global smooth scroll physics (`BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics())`).
- **Tactile Feedback**: Trigger subtle `HapticFeedback.selectionClick()` on tab/filter switches, quick actions, and confirmations; `HapticFeedback.mediumImpact()` on profile switches or major completions.
