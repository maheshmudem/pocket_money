import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_money/core/financial_engine/alert_evaluation_engine.dart';
import 'package:pocket_money/core/financial_engine/money.dart';
import 'package:pocket_money/core/utilities/id_generator.dart';
import 'package:pocket_money/features/accounts/domain/entities/financial_account_entity.dart';
import 'package:pocket_money/features/budgets/domain/entities/budget_entity.dart';
import 'package:pocket_money/features/savings_goals/domain/entities/savings_goal_entity.dart';

void main() {
  const profileId = ProfileId('prof-1');

  BudgetEntity makeBudget({
    required int limitMinor,
    required int spentMinor,
    List<BudgetCategoryAllocation> allocations = const [],
  }) {
    return BudgetEntity(
      id: 'bud-1',
      profileId: profileId,
      name: 'Monthly Spending',
      periodType: BudgetPeriodType.monthly,
      startDateUtc: '2026-11-01T00:00:00Z',
      overallLimit: Money(amountMinor: limitMinor, currencyCode: 'INR'),
      totalSpent: Money(amountMinor: spentMinor, currencyCode: 'INR'),
      rolloverEnabled: false,
      isActive: true,
      allocations: allocations,
    );
  }

  group('AlertEvaluationEngine — Pure-Dart Budget Thresholds', () {
    test('does not fire below 80% utilization (79%)', () {
      final alerts = AlertEvaluationEngine.evaluateBudgets([
        makeBudget(limitMinor: 100000, spentMinor: 79000),
      ]);
      expect(alerts, isEmpty);
    });

    test(
      'fires warning at 80% with deterministic dedupe key & masked body',
      () {
        final alerts = AlertEvaluationEngine.evaluateBudgets([
          makeBudget(limitMinor: 100000, spentMinor: 80000),
        ]);
        expect(alerts, hasLength(1));
        final a = alerts.first;
        expect(a.kind, AlertKind.budgetWarning80);
        expect(a.severity, AlertSeverity.warning);
        expect(a.dedupeKey, 'alert:bud:bud-1:2026-11-01:80');
        expect(a.deepLinkRoute, '/budgets');
        expect(a.body, contains('80%'));
        expect(a.bodyForPrivacy(hideBalances: true), isNot(contains('₹')));
        expect(a.bodyForPrivacy(hideBalances: true), contains('80%'));
      },
    );

    test('fires budgetReached100 at exactly 100%', () {
      final alerts = AlertEvaluationEngine.evaluateBudgets([
        makeBudget(limitMinor: 100000, spentMinor: 100000),
      ]);
      expect(alerts, hasLength(1));
      expect(alerts.first.kind, AlertKind.budgetReached100);
      expect(alerts.first.dedupeKey, 'alert:bud:bud-1:2026-11-01:100');
    });

    test(
      'fires critical budgetExceeded above 100% with +25% escalation tiers',
      () {
        final tier0 = AlertEvaluationEngine.evaluateBudgets([
          makeBudget(limitMinor: 100000, spentMinor: 110000),
        ]);
        final tier0Same = AlertEvaluationEngine.evaluateBudgets([
          makeBudget(limitMinor: 100000, spentMinor: 120000),
        ]);
        final tier1 = AlertEvaluationEngine.evaluateBudgets([
          makeBudget(limitMinor: 100000, spentMinor: 130000),
        ]);

        expect(tier0.first.kind, AlertKind.budgetExceeded);
        expect(tier0.first.severity, AlertSeverity.critical);
        expect(tier0.first.dedupeKey, 'alert:bud:bud-1:2026-11-01:over:0');
        // 110% and 120% share tier 0 so small extra expenses do not spam.
        expect(tier0Same.first.dedupeKey, tier0.first.dedupeKey);
        // Crossing +25% over limit escalates to tier 1.
        expect(tier1.first.dedupeKey, 'alert:bud:bud-1:2026-11-01:over:1');
      },
    );

    test('evaluates per-category 80% warning and >100% cap breach', () {
      final alerts = AlertEvaluationEngine.evaluateBudgets([
        makeBudget(
          limitMinor: 500000,
          spentMinor: 150000,
          allocations: const [
            BudgetCategoryAllocation(
              categoryId: 'cat-food',
              categoryName: 'Food & Dining',
              limitMinor: 100000,
              spentMinor: 115000,
              currencyCode: 'INR',
            ),
            BudgetCategoryAllocation(
              categoryId: 'cat-fuel',
              categoryName: 'Fuel',
              limitMinor: 50000,
              spentMinor: 42000,
              currencyCode: 'INR',
            ),
          ],
        ),
      ]);

      expect(alerts, hasLength(2));
      expect(alerts[0].kind, AlertKind.categoryExceeded);
      expect(alerts[0].title, contains('Food & Dining'));
      expect(alerts[1].kind, AlertKind.categoryWarning80);
      expect(alerts[1].title, contains('Fuel'));
    });
  });

  group('AlertEvaluationEngine — Low Balance & Goal Milestones', () {
    test(
      'flags low liquid asset accounts while ignoring liabilities and archived',
      () {
        const bankLow = FinancialAccountEntity(
          id: 'acc-1',
          profileId: profileId,
          ledgerAccountId: 'la-1',
          name: 'SBI Savings',
          accountType: FinancialAccountType.bank,
          currencyCode: 'INR',
          balance: Money(amountMinor: 45000, currencyCode: 'INR'),
          baseBalance: Money(amountMinor: 45000, currencyCode: 'INR'),
          isActive: true,
          createdAtUtc: '2026-11-01T00:00:00Z',
          updatedAtUtc: '2026-11-01T00:00:00Z',
          version: 1,
          syncStatus: 'local_only',
        );
        const cardZero = FinancialAccountEntity(
          id: 'acc-2',
          profileId: profileId,
          ledgerAccountId: 'la-2',
          name: 'Rewards Card',
          accountType: FinancialAccountType.creditCard,
          currencyCode: 'INR',
          balance: Money(amountMinor: 0, currencyCode: 'INR'),
          baseBalance: Money(amountMinor: 0, currencyCode: 'INR'),
          isActive: true,
          createdAtUtc: '2026-11-01T00:00:00Z',
          updatedAtUtc: '2026-11-01T00:00:00Z',
          version: 1,
          syncStatus: 'local_only',
        );
        const archivedCash = FinancialAccountEntity(
          id: 'acc-3',
          profileId: profileId,
          ledgerAccountId: 'la-3',
          name: 'Old Cash',
          accountType: FinancialAccountType.cash,
          currencyCode: 'INR',
          balance: Money(amountMinor: 1000, currencyCode: 'INR'),
          baseBalance: Money(amountMinor: 1000, currencyCode: 'INR'),
          isActive: false,
          createdAtUtc: '2026-11-01T00:00:00Z',
          updatedAtUtc: '2026-11-01T00:00:00Z',
          version: 1,
          syncStatus: 'local_only',
        );

        final alerts = AlertEvaluationEngine.evaluateLowBalances(
          const [bankLow, cardZero, archivedCash],
          thresholdMinor: 100000,
          dateKey: '2026-11-20',
        );

        expect(alerts, hasLength(1));
        expect(alerts.first.kind, AlertKind.lowBalance);
        expect(alerts.first.dedupeKey, 'alert:lowbal:acc-1:2026-11-20');
        expect(alerts.first.deepLinkRoute, '/accounts');
      },
    );

    test(
      'fires 50% halfway and 100% completion milestones for savings goals',
      () {
        const halfGoal = SavingsGoalEntity(
          id: 'g-1',
          profileId: profileId,
          name: 'Emergency Fund',
          targetAmount: Money(amountMinor: 100000, currencyCode: 'INR'),
          contributedAmount: Money(amountMinor: 55000, currencyCode: 'INR'),
          fundingMode: GoalFundingMode.allocated,
          status: 'active',
          createdAtUtc: '2026-11-01T00:00:00Z',
        );
        const doneGoal = SavingsGoalEntity(
          id: 'g-2',
          profileId: profileId,
          name: 'Laptop',
          targetAmount: Money(amountMinor: 80000, currencyCode: 'INR'),
          contributedAmount: Money(amountMinor: 80000, currencyCode: 'INR'),
          fundingMode: GoalFundingMode.allocated,
          status: 'completed',
          createdAtUtc: '2026-11-01T00:00:00Z',
        );

        final alerts = AlertEvaluationEngine.evaluateGoalMilestones(const [
          halfGoal,
          doneGoal,
        ]);
        expect(alerts, hasLength(2));
        expect(alerts[0].kind, AlertKind.goalMilestone50);
        expect(alerts[1].kind, AlertKind.goalCompleted100);
        expect(alerts[1].severity, AlertSeverity.celebration);
        expect(alerts[1].deepLinkRoute, '/goals');
      },
    );
  });
}
