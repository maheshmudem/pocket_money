import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_tokens.dart';

/// Classic directional tab switcher that glides incoming tabs smoothly along
/// the horizontal axis (`Offset(±0.04, 0) -> Offset.zero`) with fade dissolve.
/// Short-circuits immediately when OS reduced motion is active.
class ClassicTabSwitcher extends StatefulWidget {
  const ClassicTabSwitcher({
    required this.activeIndex,
    required this.child,
    super.key,
    this.slideDistance = 0.04,
  });

  final int activeIndex;
  final Widget child;
  final double slideDistance;

  @override
  State<ClassicTabSwitcher> createState() => _ClassicTabSwitcherState();
}

class _ClassicTabSwitcherState extends State<ClassicTabSwitcher> {
  late int _prevIndex;
  int _direction = 1;

  @override
  void initState() {
    super.initState();
    _prevIndex = widget.activeIndex;
  }

  @override
  void didUpdateWidget(covariant ClassicTabSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeIndex != _prevIndex) {
      _direction = widget.activeIndex > _prevIndex ? 1 : -1;
      _prevIndex = widget.activeIndex;
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.resolve(context, AppMotion.standard);
    final keyedChild = KeyedSubtree(
      key: ValueKey<int>(widget.activeIndex),
      child: widget.child,
    );
    if (duration == Duration.zero) {
      return keyedChild;
    }

    final reverseDuration = AppMotion.resolve(context, AppMotion.fast);
    final dir = _direction;
    final currentKey = ValueKey<int>(widget.activeIndex);

    return AnimatedSwitcher(
      duration: duration,
      reverseDuration: reverseDuration,
      switchInCurve: AppMotion.curveEmphasized,
      switchOutCurve: AppMotion.curveExit,
      transitionBuilder: (child, animation) {
        final isIncoming = child.key == currentKey;
        final offsetBegin = Offset(
          (isIncoming ? widget.slideDistance : -widget.slideDistance) * dir,
          0,
        );
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: offsetBegin,
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: keyedChild,
    );
  }
}

/// Smooth cross-fade and subtle scale settle (`0.985 -> 1.0`) for loading,
/// empty, error, filter, and wizard state transitions.
class ClassicContentSwitcher extends StatelessWidget {
  const ClassicContentSwitcher({
    required this.stateKey,
    required this.child,
    super.key,
    this.alignment = Alignment.topCenter,
  });

  final Object stateKey;
  final Widget child;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.resolve(context, AppMotion.standard);
    final keyedChild = KeyedSubtree(
      key: ValueKey<Object>(stateKey),
      child: child,
    );
    if (duration == Duration.zero) {
      return keyedChild;
    }

    final reverseDuration = AppMotion.resolve(context, AppMotion.fast);
    return AnimatedSwitcher(
      duration: duration,
      reverseDuration: reverseDuration,
      switchInCurve: AppMotion.curveEmphasized,
      switchOutCurve: AppMotion.curveExit,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: alignment,
        children: <Widget>[...previousChildren, ?currentChild],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1.0).animate(animation),
          child: child,
        ),
      ),
      child: keyedChild,
    );
  }
}

/// Smooth height + fade accordion for collapsible banners, status callouts, and
/// filter bars. Avoid nesting directly inside [IntrinsicHeight].
class ClassicExpandCollapse extends StatelessWidget {
  const ClassicExpandCollapse({
    required this.expanded,
    required this.child,
    super.key,
    this.alignment = Alignment.topCenter,
  });

  final bool expanded;
  final Widget child;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final sizeDuration = AppMotion.resolve(context, AppMotion.standard);
    final fadeDuration = AppMotion.resolve(context, AppMotion.fast);

    if (sizeDuration == Duration.zero) {
      return expanded ? child : const SizedBox.shrink();
    }

    return ClipRect(
      child: AnimatedSize(
        duration: sizeDuration,
        reverseDuration: fadeDuration,
        curve: AppMotion.curveEmphasized,
        alignment: alignment,
        child: AnimatedOpacity(
          duration: fadeDuration,
          opacity: expanded ? 1.0 : 0.0,
          curve: AppMotion.curveStandard,
          child: expanded ? child : const SizedBox(width: double.infinity),
        ),
      ),
    );
  }
}

/// Bounded odometer count-up with tabular numerals (`FontFeature.tabularFigures`),
/// respecting OS reduced-motion settings.
class ClassicAnimatedCount extends StatelessWidget {
  const ClassicAnimatedCount({
    required this.value,
    super.key,
    this.style,
    this.prefix = '',
    this.suffix = '',
  });

  final int value;
  final TextStyle? style;
  final String prefix;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.resolve(context, AppMotion.emphasis);
    final effectiveStyle = (style ?? const TextStyle()).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    if (duration == Duration.zero) {
      return Text('$prefix$value$suffix', style: effectiveStyle);
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value.toDouble()),
      duration: duration,
      curve: AppMotion.curveEmphasized,
      builder: (context, v, _) {
        return Text('$prefix${v.round()}$suffix', style: effectiveStyle);
      },
    );
  }
}

/// Subtle tactile press-scale wrapper for compact controls, pills, and action tiles.
class ClassicPressScale extends StatefulWidget {
  const ClassicPressScale({
    required this.child,
    super.key,
    this.onTap,
    this.pressedScale = 0.975,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;

  @override
  State<ClassicPressScale> createState() => _ClassicPressScaleState();
}

class _ClassicPressScaleState extends State<ClassicPressScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.resolve(context, AppMotion.fast);
    final enabled = widget.onTap != null;
    if (!enabled || duration == Duration.zero) {
      if (!enabled) return widget.child;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: widget.child,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap?.call();
      },
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: duration,
        curve: AppMotion.curveSpring,
        child: widget.child,
      ),
    );
  }
}

/// Graceful scale+fade entrance/exit wrapper for conditional Scaffold FABs.
class ClassicAnimatedFab extends StatelessWidget {
  const ClassicAnimatedFab({required this.child, super.key});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.resolve(context, AppMotion.standard);
    if (duration == Duration.zero) {
      return child ?? const SizedBox.shrink();
    }

    final reverseDuration = AppMotion.resolve(context, AppMotion.fast);
    return AnimatedSwitcher(
      duration: duration,
      reverseDuration: reverseDuration,
      switchInCurve: AppMotion.curveSpring,
      switchOutCurve: AppMotion.curveExit,
      transitionBuilder: (widget, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.84, end: 1.0).animate(animation),
          child: widget,
        ),
      ),
      child: child ?? const SizedBox.shrink(),
    );
  }
}
