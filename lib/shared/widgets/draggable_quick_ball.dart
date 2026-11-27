import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_tokens.dart';
import '../../features/accounts/presentation/pages/accounts_page.dart';
import '../../features/budgets/presentation/pages/budgets_page.dart';
import '../../features/profiles/domain/entities/profile_entity.dart';
import '../../features/transactions/domain/entities/transaction_entity.dart';
import '../../features/transactions/presentation/pages/transactions_page.dart';

/// Magnetic edge-snapping AssistiveTouch / QuickBall floating orb for the Home screen:
/// - Free 60/120fps drag anywhere on screen with magnetic left/right edge snap on release
/// - Tap to expand smart-anchored Quick Command Pod (Track Expense, Set Budget, Income, Transfer, Account)
/// - Long-press to jump straight into Track Expense
class DraggableQuickBall extends StatefulWidget {
  const DraggableQuickBall({
    required this.profile,
    super.key,
    this.bottomClearance = 16.0,
  });

  final FinancialProfile profile;
  final double bottomClearance;

  @override
  State<DraggableQuickBall> createState() => _DraggableQuickBallState();
}

class _DraggableQuickBallState extends State<DraggableQuickBall> {
  static const double _ballSize = 46;
  static const double _edgeMargin = 14;

  Offset? _position;
  bool _dragging = false;
  bool _expanded = false;

  Offset _clampAndResolve(Size area, {required double bottomClearance}) {
    final minX = _edgeMargin;
    final maxX = (area.width - _ballSize - _edgeMargin).clamp(
      minX,
      double.infinity,
    );
    final minY = _edgeMargin;
    final maxY = (area.height - _ballSize - bottomClearance).clamp(
      minY,
      double.infinity,
    );

    final current = _position ?? Offset(maxX, maxY);
    return Offset(current.dx.clamp(minX, maxX), current.dy.clamp(minY, maxY));
  }

  void _snapToNearestEdge(
    Size area,
    Offset raw, {
    required double bottomClearance,
  }) {
    final minX = _edgeMargin;
    final maxX = (area.width - _ballSize - _edgeMargin).clamp(
      minX,
      double.infinity,
    );
    final minY = _edgeMargin;
    final maxY = (area.height - _ballSize - bottomClearance).clamp(
      minY,
      double.infinity,
    );

    final centerX = raw.dx + (_ballSize / 2);
    final snappedX = centerX < (area.width / 2) ? minX : maxX;
    final snappedY = raw.dy.clamp(minY, maxY);

    setState(() {
      _dragging = false;
      _position = Offset(snappedX, snappedY);
    });
  }

  void _toggleMenu() {
    HapticFeedback.selectionClick();
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final motionFast = AppMotion.resolve(context, AppMotion.fast);
    final motionStd = AppMotion.resolve(context, AppMotion.standard);

    return LayoutBuilder(
      builder: (context, constraints) {
        final area = Size(constraints.maxWidth, constraints.maxHeight);
        if (area.width <= 0 || area.height <= 0) {
          return const SizedBox.shrink();
        }
        final bottomClearance =
            widget.bottomClearance + MediaQuery.paddingOf(context).bottom;
        final pos = _clampAndResolve(area, bottomClearance: bottomClearance);
        final onRightHalf = (pos.dx + (_ballSize / 2)) >= (area.width / 2);
        final onLowerHalf = (pos.dy + (_ballSize / 2)) >= (area.height * 0.46);

        final actions = [
          (
            key: const Key('quickball_track_expense'),
            icon: Icons.north_east_rounded,
            label: 'Track Expense',
            sub: 'Log daily spend',
            fg: cfo.expense,
            bg: cfo.expenseContainer,
            onTap: () => openAddTransactionSheet(
              context,
              widget.profile,
              initialType: TransactionType.expense,
            ),
          ),
          (
            key: const Key('quickball_set_budget'),
            icon: Icons.pie_chart_rounded,
            label: 'Set Budget',
            sub: 'Monthly limit guard',
            fg: scheme.primary,
            bg: scheme.primaryContainer,
            onTap: () => openCreateBudgetModal(
              context,
              widget.profile,
              suggestedName: 'Monthly Spending',
            ),
          ),
          (
            key: const Key('quickball_add_income'),
            icon: Icons.south_west_rounded,
            label: 'Add Income',
            sub: 'Salary or inflow',
            fg: cfo.income,
            bg: cfo.incomeContainer,
            onTap: () => openAddTransactionSheet(
              context,
              widget.profile,
              initialType: TransactionType.income,
            ),
          ),
          (
            key: const Key('quickball_transfer'),
            icon: Icons.swap_horiz_rounded,
            label: 'Transfer',
            sub: 'Move between accounts',
            fg: cfo.transfer,
            bg: cfo.transferContainer,
            onTap: () => openAddTransactionSheet(
              context,
              widget.profile,
              initialType: TransactionType.transfer,
            ),
          ),
          (
            key: const Key('quickball_add_account'),
            icon: Icons.account_balance_wallet_rounded,
            label: 'New Account',
            sub: 'Bank, cash, or card',
            fg: scheme.tertiary,
            bg: scheme.tertiaryContainer,
            onTap: () => openAddAccountModal(context, widget.profile),
          ),
        ];

        final maxMenuHeight =
            (onLowerHalf
                    ? pos.dy - 16
                    : area.height - (pos.dy + _ballSize) - 16)
                .clamp(140.0, area.height - 24);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Scrim when QuickBall menu is open
            if (_expanded)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _expanded = false),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.18),
                  ),
                ),
              ),

            // Expanded QuickBall Action Pod
            if (_expanded)
              Positioned(
                left: onRightHalf ? null : _edgeMargin,
                right: onRightHalf ? _edgeMargin : null,
                bottom: onLowerHalf ? (area.height - pos.dy + 10) : null,
                top: onLowerHalf ? null : (pos.dy + _ballSize + 10),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: (area.width - (_edgeMargin * 2)).clamp(
                      180.0,
                      256.0,
                    ),
                    maxHeight: maxMenuHeight,
                  ),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.90, end: 1.0),
                    duration: motionFast,
                    curve: Curves.easeOutCubic,
                    builder: (context, scale, child) => Transform.scale(
                      scale: scale,
                      alignment: Alignment(
                        onRightHalf ? 0.85 : -0.85,
                        onLowerHalf ? 1.0 : -1.0,
                      ),
                      child: child,
                    ),
                    child: Material(
                      elevation: 12,
                      shadowColor: cfo.cardShadow,
                      color: cfo.surfaceElevated,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusLg,
                        ),
                        side: BorderSide(color: cfo.divider),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.bolt_rounded,
                                    size: 15,
                                    color: scheme.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'QUICK ACTIONS',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: cfo.subtleText,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.7,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            for (final act in actions)
                              InkWell(
                                key: act.key,
                                borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusMd,
                                ),
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setState(() => _expanded = false);
                                  act.onTap();
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 7,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 34,
                                        height: 34,
                                        decoration: BoxDecoration(
                                          color: act.bg,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Icon(
                                          act.icon,
                                          size: 18,
                                          color: act.fg,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              act.label,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelLarge
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                            Text(
                                              act.sub,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall
                                                  ?.copyWith(
                                                    color: cfo.subtleText,
                                                    fontSize: 10.5,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Draggable Floating QuickBall Orb
            AnimatedPositioned(
              duration: _dragging ? Duration.zero : motionStd,
              curve: Curves.easeOutBack,
              left: pos.dx,
              top: pos.dy,
              child: Semantics(
                button: true,
                label: 'Quick Actions Ball',
                child: Tooltip(
                  message: 'Quick Actions',
                  child: GestureDetector(
                    key: const Key('draggable_quick_ball'),
                    onTap: _toggleMenu,
                    onLongPress: () {
                      HapticFeedback.mediumImpact();
                      setState(() => _expanded = false);
                      openAddTransactionSheet(
                        context,
                        widget.profile,
                        initialType: TransactionType.expense,
                      );
                    },
                    onPanStart: (_) {
                      setState(() {
                        _dragging = true;
                        _expanded = false;
                      });
                    },
                    onPanUpdate: (details) {
                      final cur = _clampAndResolve(
                        area,
                        bottomClearance: bottomClearance,
                      );
                      setState(() {
                        _position = Offset(
                          (cur.dx + details.delta.dx).clamp(
                            0.0,
                            area.width - _ballSize,
                          ),
                          (cur.dy + details.delta.dy).clamp(
                            0.0,
                            (area.height - _ballSize - bottomClearance + 14)
                                .clamp(0.0, area.height - _ballSize),
                          ),
                        );
                      });
                    },
                    onPanEnd: (_) {
                      HapticFeedback.lightImpact();
                      _snapToNearestEdge(
                        area,
                        _position ?? pos,
                        bottomClearance: bottomClearance,
                      );
                    },
                    onPanCancel: () => _snapToNearestEdge(
                      area,
                      _position ?? pos,
                      bottomClearance: bottomClearance,
                    ),
                    child: AnimatedScale(
                      scale: _dragging ? 1.10 : 1.0,
                      duration: motionFast,
                      child: Builder(
                        builder: (context) {
                          final isDark =
                              Theme.of(context).brightness == Brightness.dark;
                          return Container(
                            width: _ballSize,
                            height: _ballSize,
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isDark
                                  ? const Color(
                                      0xFFE5C169,
                                    ).withValues(alpha: 0.22)
                                  : Colors.white.withValues(alpha: 0.92),
                              border: Border.all(
                                color: const Color(
                                  0xFFE5C169,
                                ).withValues(alpha: isDark ? 0.56 : 0.62),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      (isDark
                                              ? const Color(0xFFCFA03B)
                                              : const Color(0xFF0E2554))
                                          .withValues(
                                            alpha: _dragging ? 0.44 : 0.28,
                                          ),
                                  blurRadius: _dragging ? 20 : 14,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: isDark
                                      ? const [
                                          Color(0xFFEEC973),
                                          Color(0xFFC99935),
                                        ]
                                      : const [
                                          Color(0xFF0C224E),
                                          Color(0xFF1A438F),
                                        ],
                                ),
                              ),
                              child: Center(
                                child: AnimatedRotation(
                                  turns: _expanded ? 0.125 : 0.0,
                                  duration: motionFast,
                                  child: Icon(
                                    Icons.add_rounded,
                                    color: isDark
                                        ? const Color(0xFF08142B)
                                        : const Color(0xFFF5DA91),
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
