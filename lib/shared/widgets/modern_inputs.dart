import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_tokens.dart';
import 'fintech_widgets.dart';

/// Flagship Neo-Fintech custom text input sharing exact visual DNA with `FintechDropdownField`.
///
/// Key UX improvements over raw Material `TextField` / `OutlineInputBorder`:
/// - Eliminates the jagged top-border floating-label notch by placing the crisp micro-label
///   cleanly *inside* the rounded elevated/tonal surface (`border: InputBorder.none` internally).
/// - Smooth focus border (`1px` hairline -> `1.8px` primary) with subtle ambient glow and
///   clean error state styling.
/// - Optional leading `IconSquircle`, built-in clear button, built-in password/PIN visibility toggle,
///   automatic `FontFeature.tabularFigures()` for numeric inputs, and accessible semantics.
class FintechTextField extends StatefulWidget {
  const FintechTextField({
    required this.label,
    super.key,
    this.controller,
    this.focusNode,
    this.hintText,
    this.helperText,
    this.errorText,
    this.leadingIcon,
    this.leadingIconColor,
    this.leadingIconBackground,
    this.trailing,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.textAlign = TextAlign.start,
    this.style,
    this.autofocus = false,
    this.obscureText = false,
    this.enableObscureToggle = false,
    this.showClearButton = false,
    this.enabled = true,
    this.readOnly = false,
    this.compact = false,
    this.tabularFigures,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.onCleared,
  });

  final String label;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final IconData? leadingIcon;
  final Color? leadingIconColor;
  final Color? leadingIconBackground;
  final Widget? trailing;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final TextAlign textAlign;
  final TextStyle? style;
  final bool autofocus;
  final bool obscureText;
  final bool enableObscureToggle;
  final bool showClearButton;
  final bool enabled;
  final bool readOnly;
  final bool compact;
  final bool? tabularFigures;
  final int maxLines;
  final int? minLines;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onCleared;

  @override
  State<FintechTextField> createState() => _FintechTextFieldState();
}

class _FintechTextFieldState extends State<FintechTextField> {
  FocusNode? _ownedFocusNode;
  TextEditingController? _ownedController;
  late bool _obscured;
  bool _hasFocus = false;

  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode!;
  TextEditingController get _controller =>
      widget.controller ?? _ownedController!;

  @override
  void initState() {
    super.initState();
    _obscured = widget.obscureText;
    if (widget.focusNode == null) {
      _ownedFocusNode = FocusNode();
    }
    if (widget.controller == null) {
      _ownedController = TextEditingController();
    }
    _hasFocus = _focusNode.hasFocus;
    _focusNode.addListener(_handleFocusChanged);
    _controller.addListener(_handleTextChanged);
  }

  @override
  void didUpdateWidget(covariant FintechTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_handleFocusChanged);
      _ownedFocusNode?.removeListener(_handleFocusChanged);
      if (widget.focusNode == null && _ownedFocusNode == null) {
        _ownedFocusNode = FocusNode();
      }
      _focusNode.addListener(_handleFocusChanged);
      _hasFocus = _focusNode.hasFocus;
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_handleTextChanged);
      _ownedController?.removeListener(_handleTextChanged);
      if (widget.controller == null && _ownedController == null) {
        _ownedController = TextEditingController();
      }
      _controller.addListener(_handleTextChanged);
    }
    if (oldWidget.obscureText != widget.obscureText &&
        !widget.enableObscureToggle) {
      _obscured = widget.obscureText;
    }
  }

  void _handleFocusChanged() {
    if (!mounted) return;
    final next = _focusNode.hasFocus;
    if (next != _hasFocus) {
      setState(() => _hasFocus = next);
    }
  }

  void _handleTextChanged() {
    if (!mounted) return;
    if (widget.showClearButton) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _controller.removeListener(_handleTextChanged);
    _ownedFocusNode?.dispose();
    _ownedController?.dispose();
    super.dispose();
  }

  bool get _isNumeric =>
      widget.tabularFigures ??
      (widget.keyboardType == TextInputType.number ||
          widget.keyboardType?.index == TextInputType.number.index);

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final duration = AppMotion.resolve(context, AppMotion.fast);
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;

    final borderColor = hasError
        ? cfo.expense
        : (_hasFocus
              ? scheme.primary
              : (widget.enabled
                    ? cfo.divider
                    : cfo.divider.withValues(alpha: 0.45)));

    final bgColor = hasError
        ? cfo.expenseContainer.withValues(alpha: isDark ? 0.28 : 0.35)
        : (_hasFocus
              ? (isDark
                    ? scheme.primaryContainer.withValues(alpha: 0.20)
                    : scheme.primaryContainer.withValues(alpha: 0.14))
              : cfo.surfaceTonal);

    final baseTextStyle =
        (widget.style ??
                Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ))
            ?.copyWith(
              color: widget.enabled ? scheme.onSurface : cfo.subtleText,
              fontFeatures: _isNumeric
                  ? const [FontFeature.tabularFigures()]
                  : widget.style?.fontFeatures,
            );

    final labelColor = hasError
        ? cfo.expense
        : (_hasFocus ? scheme.primary : cfo.subtleText);

    final showClear =
        widget.showClearButton &&
        widget.enabled &&
        !widget.readOnly &&
        _controller.text.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? () => _focusNode.requestFocus() : null,
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
                width: _hasFocus || hasError ? 1.8 : 1.0,
              ),
              boxShadow: _hasFocus && !hasError
                  ? [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.12),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              crossAxisAlignment: widget.maxLines > 1
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                if (widget.leadingIcon != null && !widget.compact) ...[
                  Padding(
                    padding: EdgeInsets.only(top: widget.maxLines > 1 ? 4 : 0),
                    child: IconSquircle(
                      icon: widget.leadingIcon!,
                      iconColor:
                          widget.leadingIconColor ??
                          (hasError
                              ? cfo.expense
                              : (_hasFocus ? scheme.primary : cfo.subtleText)),
                      backgroundColor:
                          widget.leadingIconBackground ??
                          (hasError
                              ? cfo.expenseContainer
                              : (_hasFocus
                                    ? scheme.primaryContainer.withValues(
                                        alpha: isDark ? 0.45 : 0.72,
                                      )
                                    : cfo.surfaceElevated)),
                      size: 32,
                      iconScale: 0.52,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    enabled: widget.enabled,
                    readOnly: widget.readOnly,
                    autofocus: widget.autofocus,
                    obscureText: _obscured,
                    keyboardType: widget.keyboardType,
                    textInputAction: widget.textInputAction,
                    textCapitalization: widget.textCapitalization,
                    textAlign: widget.textAlign,
                    maxLines: widget.obscureText ? 1 : widget.maxLines,
                    minLines: widget.minLines,
                    maxLength: widget.maxLength,
                    inputFormatters: widget.inputFormatters,
                    style: baseTextStyle,
                    onChanged: widget.onChanged,
                    onSubmitted: widget.onSubmitted,
                    decoration: InputDecoration(
                      labelText: widget.label,
                      hintText: widget.hintText,
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      counterText: '',
                      contentPadding: EdgeInsets.zero,
                      labelStyle: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(
                            color: labelColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 10.5,
                            height: 1.15,
                            letterSpacing: 0.15,
                          ),
                      floatingLabelStyle: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(
                            color: labelColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 11.5,
                            height: 1.15,
                            letterSpacing: 0.15,
                          ),
                      hintStyle: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(
                            color: cfo.subtleText.withValues(alpha: 0.62),
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ),
                ),
                if (showClear) ...[
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: IconButton(
                      tooltip: 'Clear',
                      padding: EdgeInsets.zero,
                      iconSize: 16,
                      color: cfo.subtleText,
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        _controller.clear();
                        widget.onChanged?.call('');
                        widget.onCleared?.call();
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                ],
                if (widget.enableObscureToggle) ...[
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: IconButton(
                      tooltip: _obscured ? 'Show' : 'Hide',
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      color: cfo.subtleText,
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        setState(() => _obscured = !_obscured);
                      },
                      icon: Icon(
                        _obscured
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ],
                if (widget.trailing != null) ...[
                  const SizedBox(width: 6),
                  widget.trailing!,
                ],
              ],
            ),
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4),
            child: Row(
              children: [
                Icon(Icons.error_outline_rounded, size: 13, color: cfo.expense),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    widget.errorText!,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cfo.expense,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          )
        else if (widget.helperText != null && widget.helperText!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4),
            child: Text(
              widget.helperText!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cfo.subtleText,
                fontSize: 11,
              ),
            ),
          ),
      ],
    );
  }
}

/// Form-integrated wrapper around [FintechTextField] supporting Flutter `Form` validation.
class FintechTextFormField extends StatelessWidget {
  const FintechTextFormField({
    required this.label,
    required this.controller,
    super.key,
    this.hintText,
    this.helperText,
    this.leadingIcon,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.obscureText = false,
    this.enableObscureToggle = false,
    this.showClearButton = false,
    this.autofocus = false,
    this.validator,
    this.onChanged,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final String? hintText;
  final String? helperText;
  final IconData? leadingIcon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final bool obscureText;
  final bool enableObscureToggle;
  final bool showClearButton;
  final bool autofocus;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      initialValue: controller.text,
      validator: (_) => validator?.call(controller.text),
      builder: (fieldState) => FintechTextField(
        label: label,
        controller: controller,
        hintText: hintText,
        helperText: helperText,
        errorText: fieldState.errorText,
        leadingIcon: leadingIcon,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        textCapitalization: textCapitalization,
        obscureText: obscureText,
        enableObscureToggle: enableObscureToggle,
        showClearButton: showClearButton,
        autofocus: autofocus,
        onChanged: (v) {
          fieldState.didChange(v);
          onChanged?.call(v);
        },
        onSubmitted: onSubmitted,
      ),
    );
  }
}

/// Unified stadium-pill search field reused across Ledger, Accounts, and Dropdown popovers.
class FintechSearchField extends StatefulWidget {
  const FintechSearchField({
    required this.controller,
    required this.hintText,
    super.key,
    this.onChanged,
    this.onClear,
    this.height = 40,
    this.elevated = false,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final double height;
  final bool elevated;

  @override
  State<FintechSearchField> createState() => _FintechSearchFieldState();
}

class _FintechSearchFieldState extends State<FintechSearchField> {
  final FocusNode _focusNode = FocusNode();
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocus);
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(covariant FintechSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
  }

  void _onFocus() {
    if (!mounted) return;
    if (_hasFocus != _focusNode.hasFocus) {
      setState(() => _hasFocus = _focusNode.hasFocus);
    }
  }

  void _onText() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocus);
    widget.controller.removeListener(_onText);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final duration = AppMotion.resolve(context, AppMotion.fast);

    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeOutCubic,
      height: widget.height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: widget.elevated ? cfo.surfaceElevated : cfo.surfaceTonal,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(
          color: _hasFocus ? scheme.primary : cfo.divider,
          width: _hasFocus ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            size: 18,
            color: _hasFocus ? scheme.primary : cfo.subtleText,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              onChanged: widget.onChanged,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: widget.hintText,
                hintStyle: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cfo.subtleText),
              ),
            ),
          ),
          if (widget.controller.text.isNotEmpty)
            SizedBox(
              width: 26,
              height: 26,
              child: IconButton(
                tooltip: 'Clear search',
                padding: EdgeInsets.zero,
                iconSize: 16,
                color: cfo.subtleText,
                onPressed: () {
                  HapticFeedback.selectionClick();
                  widget.controller.clear();
                  widget.onChanged?.call('');
                  widget.onClear?.call();
                },
                icon: const Icon(Icons.close_rounded),
              ),
            ),
        ],
      ),
    );
  }
}
