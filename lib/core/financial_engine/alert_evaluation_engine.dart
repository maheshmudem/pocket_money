import 'package:equatable/equatable.dart';

import '../../features/accounts/domain/entities/financial_account_entity.dart';
import '../../features/budgets/domain/entities/budget_entity.dart';
import '../../features/savings_goals/domain/entities/savings_goal_entity.dart';
import 'currency.dart';
import 'money.dart';
import 'monthly_tracker_engine.dart';

enum AlertSeverity { info, warning, critical, celebration }

enum AlertKind {
  budgetWarning80('budget_warning', AlertSeverity.warning),
  budgetReached100('budget_reached', AlertSeverity.warning),
  budgetExceeded('budget_exceeded', AlertSeverity.critical),
  categoryWarning80('category_warning', AlertSeverity.warning),
  categoryExceeded('category_exceeded', AlertSeverity.critical),
  lowBalance('low_balance', AlertSeverity.warning),
  goalMilestone50('goal_milestone', AlertSeverity.celebration),
  goalCompleted100('goal_completed', AlertSeverity.celebration),
  recurringDue('recurring_due', AlertSeverity.info),
  bucketReminder('bucket_reminder', AlertSeverity.info),
  testAlert('test_alert', AlertSeverity.info);

  const AlertKind(this.wireType, this.defaultSeverity);

  final String wireType;
  final AlertSeverity defaultSeverity;

  static AlertKind fromWire(String raw) => switch (raw) {
    'budget_warning' => AlertKind.budgetWarning80,
    'budget_reached' => AlertKind.budgetReached100,
    'budget_exceeded' => AlertKind.budgetExceeded,
    'category_warning' => AlertKind.categoryWarning80,
    'category_exceeded' => AlertKind.categoryExceeded,
    'low_balance' => AlertKind.lowBalance,
    'goal_milestone' => AlertKind.goalMilestone50,
    'goal_completed' => AlertKind.goalCompleted100,
    'bucket_reminder' => AlertKind.bucketReminder,
    'test_alert' => AlertKind.testAlert,
    _ => AlertKind.recurringDue,
  };
}

/// Pure-Dart immutable alert candidate produced by [AlertEvaluationEngine].
final class EvaluatedAlert extends Equatable {
  const EvaluatedAlert({
    required this.dedupeKey,
    required this.kind,
    required this.severity,
    required this.title,
    required this.body,
    required this.maskedBody,
    required this.deepLinkRoute,
  });

  /// Deterministic deduplication ID persisted in `local_notifications.id` so the
  /// exact same threshold crossing is never alerted twice in the same window.
  final String dedupeKey;
  final AlertKind kind;
  final AlertSeverity severity;
  final String title;
  final String body;
  final String maskedBody;
  final String deepLinkRoute;

  String bodyForPrivacy({required bool hideBalances}) =>
      hideBalances ? maskedBody : body;

  @override
  List<Object?> get props => [
    dedupeKey,
    kind,
    severity,
    title,
    body,
    maskedBody,
    deepLinkRoute,
  ];
}

/// 100% Pure-Dart financial alert evaluation engine (`ADR-003`).
/// Uses exact integer minor-unit comparisons (never floats) for threshold checks.
abstract final class AlertEvaluationEngine {
  static String _fmt(int amountMinor, String currencyCode) {
    final spec = CurrencyCatalog.byCode(currencyCode);
    return Money(
      amountMinor: amountMinor,
      currencyCode: currencyCode,
    ).format(spec: spec);
  }

  static String _windowKey(String isoDate) =>
      isoDate.length >= 10 ? isoDate.substring(0, 10) : isoDate;

  /// Evaluates active overall budgets and per-category allocations against
  /// 80% approaching limit, 100% exact limit hit, and >100% overspent (+25% tiers).
  static List<EvaluatedAlert> evaluateBudgets(List<BudgetEntity> budgets) {
    final alerts = <EvaluatedAlert>[];

    for (final b in budgets) {
      if (!b.isActive) continue;
      final limit = b.overallLimit.amountMinor;
      final spent = b.totalSpent.amountMinor;
      if (limit <= 0 || spent <= 0) continue;

      final ccy = b.overallLimit.currencyCode;
      final win = _windowKey(b.startDateUtc);
      final pct = (spent * 100) ~/ limit;

      if (spent > limit) {
        final overMinor = spent - limit;
        final overPct = (overMinor * 100) ~/ limit;
        final tier = overPct ~/ 25; // 0 = 101-124%, 1 = 125-149%, 2 = 150%+
        alerts.add(
          EvaluatedAlert(
            dedupeKey: 'alert:bud:${b.id}:$win:over:$tier',
            kind: AlertKind.budgetExceeded,
            severity: AlertSeverity.critical,
            title: 'Budget Limit Crossed: ${b.name}',
            body:
                'Spent ${_fmt(spent, ccy)} ($pct%) — ${_fmt(overMinor, ccy)} over your ${_fmt(limit, ccy)} limit.',
            maskedBody:
                '${b.name} crossed its spending limit ($pct%). Tap to review your budget.',
            deepLinkRoute: '/budgets',
          ),
        );
      } else if (spent == limit) {
        alerts.add(
          EvaluatedAlert(
            dedupeKey: 'alert:bud:${b.id}:$win:100',
            kind: AlertKind.budgetReached100,
            severity: AlertSeverity.warning,
            title: 'Budget Limit Reached: ${b.name}',
            body:
                'You have reached 100% (${_fmt(limit, ccy)}) of your ${b.name} budget.',
            maskedBody:
                '${b.name} has reached 100% of its spending limit. Tap to inspect.',
            deepLinkRoute: '/budgets',
          ),
        );
      } else if (spent * 100 >= limit * 80) {
        final remMinor = limit - spent;
        alerts.add(
          EvaluatedAlert(
            dedupeKey: 'alert:bud:${b.id}:$win:80',
            kind: AlertKind.budgetWarning80,
            severity: AlertSeverity.warning,
            title: 'Approaching Budget Limit: ${b.name}',
            body:
                'At $pct% (${_fmt(spent, ccy)} of ${_fmt(limit, ccy)}) — ${_fmt(remMinor, ccy)} remaining.',
            maskedBody:
                '${b.name} has reached $pct% of its budget limit. Tap to check safe daily spend.',
            deepLinkRoute: '/budgets',
          ),
        );
      }

      // Evaluate per-category caps inside this budget.
      for (final alloc in b.allocations) {
        final cLimit = alloc.limitMinor;
        final cSpent = alloc.spentMinor;
        if (cLimit <= 0 || cSpent <= 0) continue;
        final cPct = (cSpent * 100) ~/ cLimit;

        if (cSpent > cLimit) {
          final cOver = cSpent - cLimit;
          final cTier = ((cOver * 100) ~/ cLimit) ~/ 25;
          alerts.add(
            EvaluatedAlert(
              dedupeKey:
                  'alert:cat:${b.id}:${alloc.categoryId}:$win:over:$cTier',
              kind: AlertKind.categoryExceeded,
              severity: AlertSeverity.critical,
              title: 'Category Cap Crossed: ${alloc.categoryName}',
              body:
                  '${alloc.categoryName} is ${_fmt(cOver, alloc.currencyCode)} over its ${_fmt(cLimit, alloc.currencyCode)} cap ($cPct%).',
              maskedBody:
                  '${alloc.categoryName} crossed its category spending cap ($cPct%).',
              deepLinkRoute: '/budgets',
            ),
          );
        } else if (cSpent * 100 >= cLimit * 80) {
          final cRem = cLimit - cSpent;
          alerts.add(
            EvaluatedAlert(
              dedupeKey: 'alert:cat:${b.id}:${alloc.categoryId}:$win:80',
              kind: AlertKind.categoryWarning80,
              severity: AlertSeverity.warning,
              title: 'Category Cap Near Limit: ${alloc.categoryName}',
              body:
                  '${alloc.categoryName} reached $cPct% — ${_fmt(cRem, alloc.currencyCode)} left before cap.',
              maskedBody:
                  '${alloc.categoryName} reached $cPct% of its category cap.',
              deepLinkRoute: '/budgets',
            ),
          );
        }
      }
    }

    return alerts;
  }

  /// Evaluates non-archived liquid asset accounts (Bank, Cash, Wallet) against
  /// the configured low-balance floor (in profile base currency minor units).
  static List<EvaluatedAlert> evaluateLowBalances(
    List<FinancialAccountEntity> accounts, {
    required int thresholdMinor,
    required String dateKey,
  }) {
    if (thresholdMinor <= 0) return const [];
    final alerts = <EvaluatedAlert>[];

    for (final a in accounts) {
      if (a.isArchived || a.isLiability) continue;
      final isLiquid =
          a.accountType == FinancialAccountType.bank ||
          a.accountType == FinancialAccountType.cash ||
          a.accountType == FinancialAccountType.wallet;
      if (!isLiquid) continue;

      if (a.baseBalance.amountMinor <= thresholdMinor) {
        final formattedBal = _fmt(a.balance.amountMinor, a.currencyCode);
        alerts.add(
          EvaluatedAlert(
            dedupeKey: 'alert:lowbal:${a.id}:$dateKey',
            kind: AlertKind.lowBalance,
            severity: AlertSeverity.warning,
            title: 'Low Balance Alert: ${a.name}',
            body:
                '${a.name} balance is down to $formattedBal. Consider topping up or shifting funds.',
            maskedBody:
                '${a.name} dropped below your configured low-balance safety floor.',
            deepLinkRoute: '/accounts',
          ),
        );
      }
    }

    return alerts;
  }

  /// Evaluates Savings Goal 50% halfway and 100% completion milestones.
  static List<EvaluatedAlert> evaluateGoalMilestones(
    List<SavingsGoalEntity> goals,
  ) {
    final alerts = <EvaluatedAlert>[];

    for (final g in goals) {
      final target = g.targetAmount.amountMinor;
      final contributed = g.contributedAmount.amountMinor;
      if (target <= 0 || contributed <= 0) continue;

      final ccy = g.targetAmount.currencyCode;
      if (contributed >= target) {
        alerts.add(
          EvaluatedAlert(
            dedupeKey: 'alert:goal:${g.id}:100',
            kind: AlertKind.goalCompleted100,
            severity: AlertSeverity.celebration,
            title: 'Goal Reached: ${g.name}!',
            body:
                'Congratulations! You hit your ${_fmt(target, ccy)} savings target for ${g.name}.',
            maskedBody:
                'Congratulations! You reached 100% of your ${g.name} savings goal.',
            deepLinkRoute: '/goals',
          ),
        );
      } else if (contributed * 2 >= target) {
        final pct = (contributed * 100) ~/ target;
        alerts.add(
          EvaluatedAlert(
            dedupeKey: 'alert:goal:${g.id}:50',
            kind: AlertKind.goalMilestone50,
            severity: AlertSeverity.celebration,
            title: 'Halfway There: ${g.name}',
            body:
                '${g.name} is $pct% funded (${_fmt(contributed, ccy)} of ${_fmt(target, ccy)}). Keep going!',
            maskedBody:
                '${g.name} crossed $pct% of its savings target. Keep up the momentum!',
            deepLinkRoute: '/goals',
          ),
        );
      }
    }

    return alerts;
  }

  /// Evaluates scheduled Bucket List reminders and items due within 2 days.
  static List<EvaluatedAlert> evaluateBucketReminders({
    required List<BucketPlanInput> items,
    required DateTime nowUtc,
    required String currencyCode,
  }) {
    final alerts = <EvaluatedAlert>[];
    final today = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);

    for (final item in items) {
      if (item.reminderAtUtc != null) {
        final remDt = DateTime.tryParse(item.reminderAtUtc!)?.toUtc();
        if (remDt != null && !remDt.isAfter(nowUtc)) {
          final remDay = remDt.toIso8601String().substring(0, 10);
          alerts.add(
            EvaluatedAlert(
              dedupeKey: 'bucket_reminder:${item.id}:$remDay',
              kind: AlertKind.bucketReminder,
              severity: AlertSeverity.info,
              title: 'Bucket Reminder: ${item.name}',
              body:
                  'Planned purchase (${_fmt(item.estimatedMinor, currencyCode)}) reminder triggered — review in Monthly Tracker.',
              maskedBody:
                  'Planned purchase reminder for ${item.name} — review in Monthly Tracker.',
              deepLinkRoute: '/monthly?tab=1',
            ),
          );
        }
      }

      if (item.dueDateUtc != null) {
        final dueDt = DateTime.tryParse(item.dueDateUtc!)?.toUtc();
        if (dueDt != null) {
          final dueDay = DateTime.utc(dueDt.year, dueDt.month, dueDt.day);
          final diff = dueDay.difference(today).inDays;
          if (diff >= 0 && diff <= 2) {
            final dueStr = dueDay.toIso8601String().substring(0, 10);
            alerts.add(
              EvaluatedAlert(
                dedupeKey: 'bucket_due:${item.id}:$dueStr',
                kind: AlertKind.bucketReminder,
                severity: AlertSeverity.warning,
                title: diff == 0
                    ? 'Bucket Due Today: ${item.name}'
                    : 'Bucket Due Soon: ${item.name}',
                body:
                    '${item.name} (${_fmt(item.estimatedMinor, currencyCode)}) is due ${diff == 0 ? 'today' : 'in $diff day(s)'}.',
                maskedBody:
                    '${item.name} is due ${diff == 0 ? 'today' : 'in $diff day(s)'}. Review in Monthly Tracker.',
                deepLinkRoute: '/monthly?tab=1',
              ),
            );
          }
        }
      }
    }

    return alerts;
  }
}
