import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_tokens.dart';
import '../../core/financial_engine/currency.dart';
import 'fintech_widgets.dart';
import 'modern_inputs.dart';

/// Immutable option model for [FintechDropdownField].
@immutable
final class FintechDropdownOption<T> {
  const FintechDropdownOption({
    required this.value,
    required this.label,
    this.selectedLabel,
    this.subtitle,
    this.badge,
    this.icon,
    this.iconColor,
    this.iconBackground,
  });

  final T value;
  final String label;

  /// Optional shorter text shown inside the closed trigger field (e.g. `'INR'`).
  final String? selectedLabel;
  final String? subtitle;
  final String? badge;
  final IconData? icon;
  final Color? iconColor;
  final Color? iconBackground;

  String get displaySelected => selectedLabel ?? label;

  /// Shared currency picker options for `CurrencyCatalog.builtIn`.
  static List<FintechDropdownOption<String>> builtInCurrencies({
    bool compactSelected = false,
  }) => CurrencyCatalog.builtIn.values
      .map(
        (c) => FintechDropdownOption<String>(
          value: c.code,
          label: compactSelected
              ? '${c.code} — ${c.name}'
              : '${c.code} (${c.symbol}) — ${c.name}',
          selectedLabel: compactSelected ? c.code : '${c.code} (${c.symbol})',
          subtitle: compactSelected ? null : c.name,
          badge: c.symbol,
        ),
      )
      .toList(growable: false);
}

/// Flagship Neo-Fintech custom dropdown input with smart viewport-aware popover placement.
///
/// Key UX improvements over stock Material `DropdownButtonFormField`:
/// - Clean elevated/tonal field with crisp micro-label, optional leading icon,
///   and an animated rotating chevron pill (no border-slicing floating label or dated triangle caret).
/// - Exact-width, safe-margin anchored popover that opens cleanly `6dp` below the trigger
///   or flips smoothly `6dp` above when near the bottom / soft keyboard — never bleeding edge-to-edge
///   and never covering the active trigger field.
/// - Built-in instant search filter for long option lists (`>= 8` items by default, non-autofocus).
/// - Rich rows with semantic icons, subtitles, badges, and a crisp primary checkmark circle.
/// - Fully reduced-motion safe (`MediaQuery.disableAnimationsOf`) and accessible (`Semantics`).
class FintechDropdownField<T> extends StatefulWidget {
  const FintechDropdownField({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    super.key,
    this.placeholder = 'Select',
    this.leadingIcon,
    this.searchable,
    this.searchHint = 'Search options...',
    this.compact = false,
    this.minMenuWidth = 220,
    this.enabled = true,
  });

  final String label;
  final T? value;
  final List<FintechDropdownOption<T>> options;
  final ValueChanged<T>? onChanged;
  final String placeholder;
  final IconData? leadingIcon;
  final bool? searchable;
  final String searchHint;
  final bool compact;
  final double minMenuWidth;
  final bool enabled;

  @override
  State<FintechDropdownField<T>> createState() =>
      _FintechDropdownFieldState<T>();
}

class _FintechDropdownFieldState<T> extends State<FintechDropdownField<T>> {
  final GlobalKey _triggerKey = GlobalKey();
  bool _isOpen = false;

  FintechDropdownOption<T>? get _selectedOption {
    for (final opt in widget.options) {
      if (opt.value == widget.value) return opt;
    }
    return null;
  }

  Future<void> _openMenu() async {
    if (!widget.enabled || widget.onChanged == null || widget.options.isEmpty) {
      return;
    }
    final triggerContext = _triggerKey.currentContext;
    if (triggerContext == null) return;
    final box = triggerContext.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    // Dismiss any open soft keyboard gracefully without jumping layout mid-open.
    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();

    final origin = box.localToGlobal(Offset.zero);
    final triggerRect = origin & box.size;

    setState(() => _isOpen = true);

    final enableSearch = widget.searchable ?? (widget.options.length >= 8);
    final chosen = await Navigator.of(context, rootNavigator: true)
        .push<_DropdownSelection<T>>(
          _FintechDropdownRoute<T>(
            triggerRect: triggerRect,
            label: widget.label,
            options: widget.options,
            selectedValue: widget.value,
            searchable: enableSearch,
            searchHint: widget.searchHint,
            minMenuWidth: widget.minMenuWidth,
            disableAnimations: MediaQuery.disableAnimationsOf(context),
          ),
        );

    if (!mounted) return;
    setState(() => _isOpen = false);

    if (chosen != null && chosen.value != widget.value) {
      HapticFeedback.selectionClick();
      widget.onChanged?.call(chosen.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selected = _selectedOption;
    final displayText = selected?.displaySelected ?? widget.placeholder;
    final iconData = selected?.icon ?? widget.leadingIcon;
    final duration = AppMotion.resolve(context, AppMotion.fast);

    final borderColor = _isOpen
        ? scheme.primary
        : (widget.enabled ? cfo.divider : cfo.divider.withValues(alpha: 0.45));

    final bgColor = _isOpen
        ? (isDark
              ? scheme.primaryContainer.withValues(alpha: 0.22)
              : scheme.primaryContainer.withValues(alpha: 0.16))
        : cfo.surfaceTonal;

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: '${widget.label}: $displayText',
      child: Material(
        key: _triggerKey,
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          onTap: widget.enabled && widget.onChanged != null ? _openMenu : null,
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 56),
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 11 : 13,
              vertical: widget.compact ? 7 : 8,
            ),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(
                color: borderColor,
                width: _isOpen ? 1.8 : 1.0,
              ),
              boxShadow: _isOpen
                  ? [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.14),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                if (iconData != null && !widget.compact) ...[
                  IconSquircle(
                    icon: iconData,
                    iconColor: selected?.iconColor ?? scheme.primary,
                    backgroundColor:
                        selected?.iconBackground ??
                        scheme.primaryContainer.withValues(
                          alpha: isDark ? 0.45 : 0.72,
                        ),
                    size: 32,
                    iconScale: 0.52,
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: _isOpen ? scheme.primary : cfo.subtleText,
                          fontWeight: FontWeight.w600,
                          fontSize: 10.5,
                          height: 1.15,
                          letterSpacing: 0.15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              displayText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: selected != null
                                        ? scheme.onSurface
                                        : cfo.subtleText,
                                    height: 1.2,
                                  ),
                            ),
                          ),
                          if (!widget.compact &&
                              selected?.badge != null &&
                              selected!.badge!.isNotEmpty &&
                              !displayText.contains(selected.badge!)) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: cfo.surfaceElevated,
                                borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusFull,
                                ),
                                border: Border.all(
                                  color: cfo.divider.withValues(alpha: 0.85),
                                ),
                              ),
                              child: Text(
                                selected.badge!,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: cfo.subtleText,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 10,
                                    ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: widget.compact ? 24 : 26,
                  height: widget.compact ? 24 : 26,
                  decoration: BoxDecoration(
                    color: _isOpen
                        ? scheme.primary.withValues(alpha: 0.14)
                        : cfo.surfaceElevated.withValues(
                            alpha: isDark ? 0.75 : 0.9,
                          ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _isOpen
                          ? scheme.primary.withValues(alpha: 0.35)
                          : cfo.divider.withValues(alpha: 0.7),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: AnimatedRotation(
                    turns: _isOpen ? 0.5 : 0.0,
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: widget.compact ? 17 : 18,
                      color: _isOpen ? scheme.primary : cfo.subtleText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _DropdownSelection<T> {
  const _DropdownSelection(this.value);
  final T value;
}

/// Anchored popup route that calculates ideal above/below placement relative to [triggerRect]
/// while strictly respecting safe areas, keyboard insets, and horizontal breathing margins.
class _FintechDropdownRoute<T> extends PopupRoute<_DropdownSelection<T>> {
  _FintechDropdownRoute({
    required this.triggerRect,
    required this.label,
    required this.options,
    required this.selectedValue,
    required this.searchable,
    required this.searchHint,
    required this.minMenuWidth,
    required this.disableAnimations,
  });

  final Rect triggerRect;
  final String label;
  final List<FintechDropdownOption<T>> options;
  final T? selectedValue;
  final bool searchable;
  final String searchHint;
  final double minMenuWidth;
  final bool disableAnimations;

  @override
  Color? get barrierColor => Colors.black.withValues(alpha: 0.16);

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => 'Dismiss $label menu';

  @override
  Duration get transitionDuration =>
      disableAnimations ? Duration.zero : const Duration(milliseconds: 185);

  @override
  Duration get reverseTransitionDuration =>
      disableAnimations ? Duration.zero : const Duration(milliseconds: 130);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final media = MediaQuery.of(context);
    final screen = media.size;
    final safeTop = media.padding.top + 10;
    final safeBottom =
        screen.height -
        math.max(media.padding.bottom, media.viewInsets.bottom) -
        12;

    const horizontalMargin = 16.0;
    final maxAllowedWidth = math.max(
      120.0,
      screen.width - horizontalMargin * 2,
    );
    final menuWidth = math.min(
      maxAllowedWidth,
      math.max(triggerRect.width, minMenuWidth),
    );

    // Align to trigger's left edge normally; if the trigger sits on the right half
    // and menu is wider than trigger (e.g. compact Currency field), align right edges cleanly.
    double menuLeft;
    if (menuWidth > triggerRect.width &&
        triggerRect.center.dx > screen.width * 0.55) {
      menuLeft = triggerRect.right - menuWidth;
    } else {
      menuLeft = triggerRect.left;
    }
    menuLeft = menuLeft.clamp(
      horizontalMargin,
      math.max(horizontalMargin, screen.width - horizontalMargin - menuWidth),
    );

    const gap = 6.0;
    final spaceBelow = math.max(0.0, safeBottom - triggerRect.bottom - gap);
    final spaceAbove = math.max(0.0, triggerRect.top - safeTop - gap);

    final estimatedItemHeight = options.any((o) => o.subtitle != null)
        ? 54.0
        : 46.0;
    final searchHeaderHeight = searchable ? 52.0 : 0.0;
    final idealHeight = math.min(
      320.0,
      searchHeaderHeight + options.length * estimatedItemHeight + 18.0,
    );

    final openBelow = spaceBelow >= idealHeight || spaceBelow >= spaceAbove;
    final maxMenuHeight = math.max(
      110.0,
      math.min(340.0, openBelow ? spaceBelow : spaceAbove),
    );

    final double? topPos = openBelow ? triggerRect.bottom + gap : null;
    final double? bottomPos = openBelow
        ? null
        : (screen.height - triggerRect.top + gap);

    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    final popover = _FintechDropdownPopover<T>(
      label: label,
      options: options,
      selectedValue: selectedValue,
      searchable: searchable,
      searchHint: searchHint,
      maxHeight: maxMenuHeight,
    );

    final animatedPopover = disableAnimations
        ? popover
        : FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              alignment: openBelow
                  ? Alignment.topCenter
                  : Alignment.bottomCenter,
              scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
              child: popover,
            ),
          );

    return Stack(
      children: [
        Positioned(
          left: menuLeft,
          top: topPos,
          bottom: bottomPos,
          width: menuWidth,
          child: animatedPopover,
        ),
      ],
    );
  }
}

class _FintechDropdownPopover<T> extends StatefulWidget {
  const _FintechDropdownPopover({
    required this.label,
    required this.options,
    required this.selectedValue,
    required this.searchable,
    required this.searchHint,
    required this.maxHeight,
  });

  final String label;
  final List<FintechDropdownOption<T>> options;
  final T? selectedValue;
  final bool searchable;
  final String searchHint;
  final double maxHeight;

  @override
  State<_FintechDropdownPopover<T>> createState() =>
      _FintechDropdownPopoverState<T>();
}

class _FintechDropdownPopoverState<T>
    extends State<_FintechDropdownPopover<T>> {
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Scroll selected item cleanly into view on first frame if far down the list.
    final idx = widget.options.indexWhere(
      (o) => o.value == widget.selectedValue,
    );
    if (idx > 3) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollCtrl.hasClients) return;
        final target = math.max(0.0, (idx - 1) * 46.0);
        _scrollCtrl.jumpTo(
          target.clamp(0.0, _scrollCtrl.position.maxScrollExtent),
        );
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  List<FintechDropdownOption<T>> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.options;
    return widget.options
        .where(
          (o) =>
              o.label.toLowerCase().contains(q) ||
              (o.subtitle?.toLowerCase().contains(q) ?? false) ||
              (o.badge?.toLowerCase().contains(q) ?? false),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = _filtered;

    return Material(
      key: const Key('fintech_dropdown_popover'),
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        child: Container(
          decoration: BoxDecoration(
            color: cfo.surfaceElevated,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: cfo.divider),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.50 : 0.13),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.searchable)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                  child: FintechSearchField(
                    key: const Key('fintech_dropdown_search_field'),
                    controller: _searchCtrl,
                    hintText: widget.searchHint,
                    height: 38,
                    onChanged: (v) => setState(() => _query = v),
                    onClear: () => setState(() => _query = ''),
                  ),
                ),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        size: 24,
                        color: cfo.subtleText,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'No matching options',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cfo.subtleText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Flexible(
                  child: Scrollbar(
                    controller: _scrollCtrl,
                    radius: const Radius.circular(8),
                    child: ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.all(6),
                      shrinkWrap: true,
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final opt = items[index];
                        final isSelected = opt.value == widget.selectedValue;
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: index < items.length - 1 ? 2 : 0,
                          ),
                          child: Material(
                            color: isSelected
                                ? scheme.primaryContainer.withValues(
                                    alpha: isDark ? 0.50 : 0.62,
                                  )
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => Navigator.of(context)
                                  .pop<_DropdownSelection<T>>(
                                    _DropdownSelection<T>(opt.value),
                                  ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 9,
                                ),
                                child: Row(
                                  children: [
                                    if (opt.icon != null) ...[
                                      IconSquircle(
                                        icon: opt.icon!,
                                        iconColor:
                                            opt.iconColor ??
                                            (isSelected
                                                ? scheme.primary
                                                : cfo.subtleText),
                                        backgroundColor:
                                            opt.iconBackground ??
                                            (isSelected
                                                ? scheme.primary.withValues(
                                                    alpha: 0.16,
                                                  )
                                                : cfo.surfaceTonal),
                                        size: 30,
                                        iconScale: 0.52,
                                      ),
                                      const SizedBox(width: 10),
                                    ],
                                    Expanded(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            opt.label,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  fontWeight: isSelected
                                                      ? FontWeight.w800
                                                      : FontWeight.w600,
                                                  color: isSelected
                                                      ? scheme.primary
                                                      : scheme.onSurface,
                                                ),
                                          ),
                                          if (opt.subtitle != null &&
                                              opt.subtitle!.isNotEmpty) ...[
                                            const SizedBox(height: 1),
                                            Text(
                                              opt.subtitle!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall
                                                  ?.copyWith(
                                                    color: cfo.subtleText,
                                                    fontSize: 11,
                                                  ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (opt.badge != null &&
                                        opt.badge!.isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? scheme.primary.withValues(
                                                  alpha: 0.15,
                                                )
                                              : cfo.surfaceTonal,
                                          borderRadius: BorderRadius.circular(
                                            AppSpacing.radiusFull,
                                          ),
                                        ),
                                        child: Text(
                                          opt.badge!,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: isSelected
                                                    ? scheme.primary
                                                    : cfo.subtleText,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 10.5,
                                              ),
                                        ),
                                      ),
                                    ],
                                    if (isSelected) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        width: 20,
                                        height: 20,
                                        decoration: BoxDecoration(
                                          color: scheme.primary,
                                          shape: BoxShape.circle,
                                        ),
                                        alignment: Alignment.center,
                                        child: const Icon(
                                          Icons.check_rounded,
                                          size: 13,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
