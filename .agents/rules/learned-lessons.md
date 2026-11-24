# Learned Engineering & UI Lessons (Battle-Tested)

Distilled root causes and permanent rules captured from real builds, tests, and live device QA so they are never repeated.

---

## Coding & Flutter Framework Gotchas

1. **Flutter 3.41+ `cacheExtent` Deprecation**:
   - *Trap*: `cacheExtent` on `ListView` / `CustomScrollView` triggers `deprecated_member_use` under `flutter analyze --fatal-infos`.
   - *Rule*: Always import `package:flutter/rendering.dart` and use `scrollCacheExtent: const ScrollCacheExtent.pixels(640)`.
2. **`TextTheme` Color Overrides Semantic Fallback Colors**:
   - *Trap*: `Theme.of(context).textTheme.bodyMedium` carries an explicit `color: onSurface`, so `style?.color ?? semanticColor` silently ignores `semanticColor`.
   - *Rule*: When a widget accepts an explicit semantic mode (e.g., `MoneyText(semanticKind: 'income' | 'expense' | 'transfer')`), prioritize the resolved semantic color when `semanticKind != null`.
3. **`SweepGradient` Round-Cap Wraparound Bleed**:
   - *Trap*: Drawing a `StrokeCap.round` arc with `SweepGradient` starting at `startAngle` bleeds the gradient's end color into the rounded start cap.
   - *Rule*: Pad the gradient rotation backward by `capPad = 0.14`, set `tileMode: TileMode.clamp`, and pin stops (`[0.0, 0.06, 1.0]`).
4. **Drift `query.watch()` Deadlock in `FakeAsync` Widget Tests**:
   - *Trap*: Subscribing to Drift's `query.watch()` from a root app cubit can hang `await AppDatabase.close()` during widget test teardown due to Drift's `StreamQueryStore` cleanup timer inside `FakeAsync`.
   - *Rule*: Use a pure-Dart broadcast `StreamController` emitted on repository/coordinator mutations paired with direct async queries and epoch staleness guards instead of long-lived root `query.watch()` streams.
5. **Never Key an Animation Wrapper Around `StatefulNavigationShell`**:
   - *Trap*: Putting `ValueKey(branchIndex)` on a wrapper around GoRouter's `StatefulNavigationShell` remounts child subtrees and discards scroll state on every tab switch.
   - *Rule*: Drive tab transitions with a `SingleTickerProviderStateMixin` `AnimationController` + `AnimatedBuilder(child: child)` triggered on index change.
6. **`flutter_local_notifications` v23+ Named API & Android Desugaring**:
   - *Trap*: Older `19.x` conflicts with `pdf 3.13+` (`xml` v6 vs v7), and `v23+` uses named parameters (`settings:`, `id:`, `notificationDetails:`) plus requires Android SDK 37, AGP `9.1.0`, Gradle `9.3.1`, and core library desugaring (`desugar_jdk_libs:2.1.4`).
   - *Rule*: Use `flutter_local_notifications ^23.0.3` + `timezone ^0.11.2`, inject an `InMemoryNotificationDispatcher` in tests, and configure `compileSdk = 37`, AGP `9.1.0`, Gradle `9.3.1`, and `isCoreLibraryDesugaringEnabled = true`.

---

## Layout, Overflow & Modern UI Gotchas

4. **`PopupMenuItem` Narrow Horizontal Constraint Overflow**:
   - *Trap*: Material `PopupMenuItem` constrains rows to `~256dp`; unflexed `Row(Icon, Text)` overflows on slightly longer labels or `1.5x` font scale.
   - *Rule*: Always wrap `Text` inside `PopupMenuItem` rows in `Flexible(..., child: Text(..., maxLines: 1, overflow: TextOverflow.ellipsis))`.
5. **Right-Aligned Currency & Header Pill Overflows (`360x800`)**:
   - *Trap*: Unconstrained `MoneyText` or pills inside a `Row` overflow narrow mobile screens.
   - *Rule*: Wrap left titles in `Expanded(Row(Flexible(Text), ...))` and right amounts/pills in `ConstrainedBox(maxWidth: ...) + FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight)`.
6. **Subtitle Share Percentage Truncation (`"Bank Account • 95% sh..."`)**:
   - *Trap*: Appending share percentages to account subtitles causes ugly truncation on mobile cards.
   - *Rule*: Keep the subtitle clean (`accountType.label`) and place the percentage in a dedicated right-aligned tabular readout beside the progress bar.
7. **Zero Raw Stock `AlertDialog` Popups**:
   - *Trap*: Default Material `AlertDialog` boxes clash harshly with modern elevated Neo-Fintech screens.
   - *Rule*: Always launch popups with `showModernDialog` + `ModernDialogShell` or `showModernConfirmDialog` (frosted backdrop, `3px` semantic trim, icon squircle header, live preview where helpful, keyboard-safe scroll, rounded footer actions).
8. **Cohesive Light & Dark Hero Surfaces**:
   - *Trap*: Giant dark full-bleed purple gradient cards look dated/heavy on Daylight Light screens and eat above-the-fold height.
   - *Rule*: Use compact theme-native `FintechAccentCard` surfaces (`surfaceElevated`, `3px` top gradient trim, subtle ambient radial glow, hairline-divided `FintechFlatActionBar`) across all main tabs.
9. **Zero Stock `DropdownButtonFormField` Menus & Nullable Popover Results**:
   - *Trap*: Stock Material `DropdownButtonFormField` bleeds edge-to-edge across the viewport, covers the active field, lacks search/icons, and returning `T?` directly from a `PopupRoute` confuses selecting a `null` option with barrier dismissal.
   - *Rule*: Always use `FintechDropdownField<T>` ([modern_dropdown.dart](file:///c:/Users/1070/Desktop/Appversion/pocket_money/lib/shared/widgets/modern_dropdown.dart)) with clean uniform `1px` popover borders (no stray top accent stripe), exact-width / right-edge viewport-aware above-or-below placement (`spaceBelow >= idealHeight || spaceBelow >= spaceAbove`), and a private `_DropdownSelection<T>` wrapper for nullable selections.
10. **Zero Hardcoded Raw `TextField`s & Top-Border Floating-Label Notches**:
   - *Trap*: Scattering raw `TextField` / `TextFormField` with Material `OutlineInputBorder` causes labels to slice awkwardly across the top border and duplicates obscure/clear/search boilerplate across screens.
   - *Rule*: Always use `FintechTextField`, `FintechTextFormField`, or `FintechSearchField` ([modern_inputs.dart](file:///c:/Users/1070/Desktop/Appversion/pocket_money/lib/shared/widgets/modern_inputs.dart)), which wrap an internal borderless `TextField` (`border: InputBorder.none`, `floatingLabelBehavior: FloatingLabelBehavior.always`) inside a uniform rounded container so labels sit cleanly inside without any top-border notch while keeping `find.widgetWithText(TextField, label)` tests compatible.

---

## Live Device QA & Windows Tooling Gotchas

9. **Windows PowerShell Binary Screenshot Corruption**:
   - *Trap*: Redirecting `adb exec-out screencap -p > shot.png` in PowerShell encodes stdout as text and corrupts the PNG binary.
   - *Rule*: Always capture to `/sdcard/tmp.png` and retrieve via `adb -s <serial> pull /sdcard/tmp.png "<dest>"`.
10. **Instant Android Emulator Light/Dark Switching**:
    - *Rule*: Toggle Android system dark mode cleanly via `adb -s <serial> shell cmd uimode night yes` and restore with `night no` (works instantaneously when the app uses `ThemeMode.system` / `Auto`).
11. **Elastic Scroll Settle Delay Before Tapping**:
    - *Trap*: Fast swipes under `BouncingScrollPhysics` keep drifting for `~800ms`, causing immediate coordinate taps to miss.
    - *Rule*: Use deliberate `1000–1200ms` swipes followed by `1200ms` settle sleep before tapping scrolled controls.
12. **Never Wipe Live Device/Emulator App Data**:
    - *Rule*: Always upgrade with `adb -s <serial> install -r <apk>`. Never run `adb shell pm clear` unless the user explicitly asks to wipe data.
13. **Android 5+ Monochrome Status-Bar Notification Icon**:
    - *Trap*: Passing an opaque `@mipmap/ic_launcher` to `AndroidInitializationSettings` renders as a solid white square in the Android status bar because Android masks small notification icons using only the alpha channel.
    - *Rule*: Always create a transparent monochrome white vector drawable (`res/drawable/ic_stat_*.xml`) and pair it with a semantic accent `color:` on `AndroidNotificationDetails`.
