import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/financial_engine/currency.dart';
import '../../../../core/financial_engine/life_stage_planner_engine.dart';
import '../../../../core/financial_engine/money.dart';
import '../../../../core/utilities/clock.dart';
import '../../../../shared/widgets/classic_motion.dart';
import '../../../../shared/widgets/credit_salary_dialog.dart';
import '../../../../shared/widgets/enterprise_layout.dart';
import '../../../../shared/widgets/fintech_widgets.dart';
import '../../../../shared/widgets/modern_dialogs.dart';
import '../../../../shared/widgets/modern_inputs.dart';
import '../../../../shared/widgets/trendy_fintech_gauges.dart';
import '../../../dashboard/presentation/bloc/dashboard_bloc.dart';
import '../../../notifications/presentation/bloc/notifications_cubit.dart';
import '../../../profiles/domain/entities/profile_entity.dart';
import '../../../profiles/presentation/bloc/active_profile_cubit.dart';
import '../../../settings/presentation/bloc/settings_cubit.dart';
import '../../../transactions/presentation/bloc/transactions_bloc.dart';
import '../../data/life_stage_planner_service.dart';
import '../widgets/bottom_up_expense_sheet_card.dart';

/// `SCR-LIFE-001` — 100% Free, Offline Life-Stage & EMI Money Planner.
///
/// Adapts budgeting, saving ratios, emergency shields, and EMI/debt guardrails
/// to real-world personas (Bachelor, Family with Kids, Married Couple, Student,
/// Supporting Parents, Freelancer/Business, Pre-Retirement).
class LifeStagePlannerPage extends StatefulWidget {
  const LifeStagePlannerPage({super.key, this.initialTab = 0});

  /// `0` = My Status & Budget, `1` = EMI & Debt Guard, `2` = Save & Protect.
  final int initialTab;

  @override
  State<LifeStagePlannerPage> createState() => _LifeStagePlannerPageState();
}

class _LifeStagePlannerPageState extends State<LifeStagePlannerPage> {
  late int _activeTab;
  LifeStageWorkspaceSnapshot? _snapshot;
  bool _loading = true;
  bool _savingCashFlow = false;
  bool _applyingBudget = false;
  bool _creatingGoal = false;
  String? _loadedProfileId;

  // Interactive controls state
  final _affordLoanCtrl = TextEditingController(text: '500000');
  final _affordRateCtrl = TextEditingController(text: '10.5');
  final _affordTenureCtrl = TextEditingController(text: '36');

  DebtPayoffStrategy _selectedStrategy = DebtPayoffStrategy.avalanche;
  double _extraPrepayMajor = 2000;
  bool _useSampleLoans = false;

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab.clamp(0, 2);
  }

  @override
  void dispose() {
    _affordLoanCtrl.dispose();
    _affordRateCtrl.dispose();
    _affordTenureCtrl.dispose();
    super.dispose();
  }

  int _parseToMinor(String raw, String ccy) {
    final clean = raw.trim().replaceAll(',', '');
    if (clean.isEmpty) return 0;
    final spec = CurrencyCatalog.requireByCode(ccy);
    return Money.parseDecimal(clean, currency: spec).valueOrNull?.amountMinor ??
        0;
  }

  Future<void> _reload(FinancialProfile profile) async {
    _loadedProfileId = profile.id.value;
    setState(() => _loading = true);
    final res = await GetIt.I<LifeStagePlannerService>().loadWorkspace(
      profile: profile,
    );
    if (!mounted) return;
    final snap = res.valueOrNull;
    setState(() {
      _snapshot = snap;
      _loading = false;
    });
  }

  Future<void> _saveExpenseProfile(
    BuildContext context,
    FinancialProfile profile,
    MonthlyExpenseProfile updated, {
    String? toastMessage,
  }) async {
    if (_savingCashFlow) return;
    setState(() => _savingCashFlow = true);
    try {
      await GetIt.I<LifeStagePlannerService>().saveExpenseProfile(
        profileId: profile.id,
        expenseProfile: updated,
      );
      if (!mounted) return;
      await _reload(profile);
      if (context.mounted && toastMessage != null) {
        showFintechToast(context, toastMessage, tone: FintechToastTone.success);
      }
    } finally {
      if (mounted) setState(() => _savingCashFlow = false);
    }
  }

  Future<void> _autoFillFromLedger(
    BuildContext context,
    FinancialProfile profile,
  ) async {
    if (_savingCashFlow) return;
    setState(() => _savingCashFlow = true);
    try {
      final svc = GetIt.I<LifeStagePlannerService>();
      final res = await svc.autoFillExpensesFromLedger(profile: profile);
      if (!context.mounted) return;
      final filled = res.valueOrNull;
      if (filled == null) {
        showFintechToast(
          context,
          'Could not read recent ledger transactions.',
          tone: FintechToastTone.danger,
        );
        return;
      }
      if (!filled.hasAnyEnteredExpenses && filled.totalIncomeMinor <= 0) {
        showFintechToast(
          context,
          'No recurring bills or expenses logged yet — tap Estimate Typical to start.',
          tone: FintechToastTone.info,
        );
        return;
      }
      await svc.saveExpenseProfile(
        profileId: profile.id,
        expenseProfile: filled,
      );
      if (!mounted) return;
      await _reload(profile);
      if (context.mounted) {
        showFintechToast(
          context,
          'Auto-filled real income & bills from your ledger.',
          tone: FintechToastTone.success,
        );
      }
    } finally {
      if (mounted) setState(() => _savingCashFlow = false);
    }
  }

  Future<void> _estimateTypicalExpenses(
    BuildContext context,
    FinancialProfile profile,
    LifeStageWorkspaceSnapshot snap,
    int primaryMinor,
    int secondaryMinor,
    int existingManualEmiMinor,
  ) async {
    final spec = CurrencyCatalog.requireByCode(snap.currencyCode);
    final unit = math.pow(10, spec.minorUnit).toInt();
    final effectivePrimary = (primaryMinor + secondaryMinor) > 0
        ? primaryMinor
        : (snap.incomePoolMinor > 0 ? snap.incomePoolMinor : 60000 * unit);
    final estimated = LifeStagePlannerEngine.estimateTypicalExpenses(
      primaryIncomeMinor: effectivePrimary,
      secondaryIncomeMinor: secondaryMinor,
      targets: snap.targets,
      currencyCode: snap.currencyCode,
      trackedLoanEmiMinor: snap.cashFlowPlan.trackedLoanEmiMinor,
    ).copyWith(manualEmiMinor: existingManualEmiMinor);

    await _saveExpenseProfile(
      context,
      profile,
      estimated,
      toastMessage:
          'Estimated typical ${snap.targets.status.shortLabel} expenses — tweak any row to match yours.',
    );
  }

  Future<void> _updateProfilePrefs(
    FinancialProfile profile, {
    required LifeStageStatus status,
    required int dependentsCount,
    required HousingMode housingMode,
    int? incomeMinor,
  }) async {
    HapticFeedback.selectionClick();
    await GetIt.I<LifeStagePlannerService>().savePreferences(
      profileId: profile.id,
      status: status,
      dependentsCount: dependentsCount,
      housingMode: housingMode,
      plannedMonthlyIncomeMinor: incomeMinor,
    );
    if (mounted) await _reload(profile);
  }

  Future<void> _applyLifeStageBudget(
    BuildContext context,
    FinancialProfile profile,
    LifeStageWorkspaceSnapshot snap,
  ) async {
    if (_applyingBudget || !profile.permissions.canManageCategoriesAndBudgets) {
      return;
    }
    final useBottomUp =
        snap.expenseProfile.hasAnyEnteredExpenses &&
        snap.cashFlowPlan.budgetEnvelopes.isNotEmpty;
    final envelopeCount = useBottomUp
        ? snap.cashFlowPlan.budgetEnvelopes.length
        : snap.blueprint.categoryLimitsMap.length;
    final totalMinor = useBottomUp
        ? snap.cashFlowPlan.budgetEnvelopes.fold<int>(
            0,
            (s, e) => s + e.amountMinor,
          )
        : snap.blueprint.totalRecommendedCategoriesMinor;

    if (envelopeCount == 0 || totalMinor <= 0) {
      showFintechToast(
        context,
        'Set a monthly income or estimate expenses above first so budget envelopes can be computed.',
        tone: FintechToastTone.info,
      );
      return;
    }
    final totalFmt = Money(
      amountMinor: totalMinor,
      currencyCode: snap.currencyCode,
    ).format();
    final confirmed = await showModernConfirmDialog(
      context: context,
      title: 'Apply ${snap.targets.status.shortLabel} Budget?',
      subtitle: '$envelopeCount category envelopes',
      icon: lifeStageIcon(snap.targets.status),
      accent: ModernDialogAccent.success,
      confirmLabel: 'Apply $totalFmt',
      message: useBottomUp
          ? 'Save "${snap.targets.status.shortLabel} Master Budget" ($totalFmt/mo) built from your real expenses & guilt-free cap? Missing categories like Insurance or Subscriptions will be created automatically.'
          : 'Save "${snap.targets.status.shortLabel} Master Budget" ($totalFmt/mo) tailored for ${snap.targets.status.title}? You can fine-tune any category anytime in Budgets.',
    );
    if (confirmed != true || !context.mounted) return;

    setState(() => _applyingBudget = true);
    try {
      final dashBloc = context.read<DashboardBloc?>();
      final res = await GetIt.I<LifeStagePlannerService>().applyLifeStageBudget(
        profile: profile,
        snapshot: snap,
      );
      if (!context.mounted) return;
      if (res.isSuccess) {
        dashBloc?.add(const DashboardRefreshRequested());
        showFintechToast(
          context,
          'Applied "${snap.targets.status.shortLabel} Master Budget" ($totalFmt/mo).',
          tone: FintechToastTone.success,
        );
        await _reload(profile);
      } else {
        showFintechToast(
          context,
          res.failureOrNull?.message ?? 'Could not apply budget.',
          tone: FintechToastTone.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _applyingBudget = false);
    }
  }

  Future<void> _createEmergencyGoal(
    BuildContext context,
    FinancialProfile profile,
    LifeStageWorkspaceSnapshot snap,
  ) async {
    if (_creatingGoal || !profile.permissions.canManageCategoriesAndBudgets) {
      return;
    }
    setState(() => _creatingGoal = true);
    try {
      final dashBloc = context.read<DashboardBloc?>();
      final res = await GetIt.I<LifeStagePlannerService>()
          .createEmergencyShieldGoal(profile: profile, shield: snap.shield);
      if (!context.mounted) return;
      if (res.isSuccess) {
        dashBloc?.add(const DashboardRefreshRequested());
        showFintechToast(
          context,
          'Created Emergency Shield (${snap.shield.targetMonths} Months) goal!',
          tone: FintechToastTone.success,
        );
        await _reload(profile);
      } else {
        showFintechToast(
          context,
          res.failureOrNull?.message ?? 'Could not create emergency goal.',
          tone: FintechToastTone.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _creatingGoal = false);
    }
  }

  T? _maybeRead<T>(BuildContext context) {
    try {
      return context.read<T>();
    } catch (_) {
      return null;
    }
  }

  Future<void> _openCreditSalaryDialog(
    BuildContext context,
    FinancialProfile profile,
    LifeStageWorkspaceSnapshot snap,
  ) async {
    if (snap.liquidAccounts.isEmpty ||
        !profile.permissions.canPostTransaction) {
      showFintechToast(
        context,
        'Add a bank or cash account first to credit salary.',
        tone: FintechToastTone.info,
      );
      return;
    }
    final now = GetIt.I<UtcClock>().nowUtc();
    const monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final monthLabel = '${monthNames[now.month - 1]} ${now.year}';

    final draft = await showModernDialog<CreditSalaryDraft>(
      context: context,
      builder: (_) => CreditSalaryDialog(
        currencyCode: snap.currencyCode,
        monthLabel: monthLabel,
        defaultAmountMinor: snap.incomePoolMinor,
        accounts: snap.liquidAccounts,
        preferredAccountId: snap.salaryAccountId,
        alreadyCredited: snap.salaryCreditedThisMonth,
      ),
    );
    if (draft == null || !context.mounted) return;

    final dashBloc = _maybeRead<DashboardBloc>(context);
    final txBloc = _maybeRead<TransactionsBloc>(context);
    final notifCubit = _maybeRead<NotificationsCubit>(context);

    final res = await GetIt.I<LifeStagePlannerService>()
        .creditMonthlySalaryToAccount(
          profile: profile,
          accountId: draft.accountId,
          amountMinor: draft.amountMinor,
          year: now.year,
          month: now.month,
          createRecurringRule: draft.createRecurringRule,
          forceDuplicate: snap.salaryCreditedThisMonth,
        );
    if (!context.mounted) return;
    if (res.isSuccess) {
      final info = res.valueOrNull!;
      HapticFeedback.mediumImpact();
      dashBloc?.add(const DashboardRefreshRequested());
      txBloc?.add(const TransactionsLoadRequested());
      notifCubit?.triggerCelebration();
      showFintechToast(
        context,
        info.recurringRuleCreated
            ? 'Salary credited to ${info.accountName} & monthly reminder enabled.'
            : 'Salary credited to ${info.accountName}.',
        tone: FintechToastTone.success,
      );
      await _reload(profile);
    } else {
      showFintechToast(
        context,
        res.failureOrNull?.message ?? 'Could not credit salary.',
        tone: FintechToastTone.danger,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ActiveProfileCubit>().state.activeProfile;
    final hideBalances = context.watch<SettingsCubit>().state.hideBalances;

    if (profile == null) {
      return const Scaffold(
        body: EmptyStateView(
          icon: Icons.family_restroom_rounded,
          title: 'No active profile',
          description: 'Select a profile to personalize your life-stage plan.',
        ),
      );
    }
    if (_loadedProfileId != profile.id.value) {
      _loadedProfileId = profile.id.value;
      Future.microtask(() => _reload(profile));
    }

    final snap = _snapshot;
    final canManage = profile.permissions.canManageCategoriesAndBudgets;

    return Scaffold(
      appBar: EnterpriseAppBar(
        title: const Text('Life & EMI Planner'),
        actions: [
          if (snap != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: LifeStageBadgePill(
                  status: snap.targets.status,
                  compact: true,
                ),
              ),
            ),
        ],
      ),
      body: ClassicContentSwitcher(
        stateKey: _loading && snap == null
            ? 'loading'
            : snap == null
            ? 'empty'
            : 'loaded',
        child: _loading && snap == null
            ? const DashboardSkeletonView()
            : snap == null
            ? EmptyStateView(
                icon: Icons.family_restroom_rounded,
                title: 'Unable to load Life-Stage Planner',
                description:
                    'Pull down or tap retry to sync your local ledger.',
                actionLabel: 'Retry',
                onAction: () => _reload(profile),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.xs,
                      AppSpacing.md,
                      AppSpacing.xs,
                    ),
                    child: EnterprisePageContainer(
                      maxWidth: AppBreakpoints.maxContentWidth,
                      child: FintechSegmentedControl<int>(
                        key: const Key('life_mode_tabs'),
                        selected: _activeTab,
                        options: const [
                          FintechSegmentOption(
                            value: 0,
                            label: 'My Status',
                            icon: Icons.person_outline_rounded,
                          ),
                          FintechSegmentOption(
                            value: 1,
                            label: 'EMI & Debt',
                            icon: Icons.speed_rounded,
                          ),
                          FintechSegmentOption(
                            value: 2,
                            label: 'Save & Shield',
                            icon: Icons.shield_outlined,
                          ),
                        ],
                        onChanged: (idx) {
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          setState(() => _activeTab = idx);
                        },
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClassicTabSwitcher(
                      activeIndex: _activeTab,
                      child: switch (_activeTab) {
                        1 => _buildEmiAndDebtTab(
                          context,
                          profile: profile,
                          snap: snap,
                          masked: hideBalances,
                        ),
                        2 => _buildSaveAndProtectTab(
                          context,
                          profile: profile,
                          snap: snap,
                          masked: hideBalances,
                          canManage: canManage,
                        ),
                        _ => _buildStatusAndBudgetTab(
                          context,
                          profile: profile,
                          snap: snap,
                          masked: hideBalances,
                          canManage: canManage,
                        ),
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 0: MY STATUS & BUDGET BLUEPRINT
  // ---------------------------------------------------------------------------
  Widget _buildStatusAndBudgetTab(
    BuildContext context, {
    required FinancialProfile profile,
    required LifeStageWorkspaceSnapshot snap,
    required bool masked,
    required bool canManage,
  }) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final t = snap.targets;
    final bp = snap.blueprint;
    final ccy = snap.currencyCode;

    final idealSegments = <MoneyBarSegment>[
      MoneyBarSegment(
        label: 'Needs',
        percent: t.needsPct.toDouble(),
        color: scheme.primary,
      ),
      MoneyBarSegment(
        label: 'Wants',
        percent: t.wantsPct.toDouble(),
        color: cfo.warning,
      ),
      if (t.taxPct > 0)
        MoneyBarSegment(
          label: 'Tax',
          percent: t.taxPct.toDouble(),
          color: cfo.expense,
        ),
      MoneyBarSegment(
        label: 'Savings',
        percent: t.savingsPct.toDouble(),
        color: cfo.income,
      ),
    ];

    final actualDenom = math.max(bp.incomePoolMinor, bp.actualTotalSpendMinor);
    final actualNeedsPct = actualDenom > 0
        ? (bp.actualNeedsMinor * 100.0 / actualDenom)
        : 0.0;
    final actualWantsPct = actualDenom > 0
        ? (bp.actualWantsMinor * 100.0 / actualDenom)
        : 0.0;
    final actualSavedPct = actualDenom > 0
        ? (math.max(0, bp.incomePoolMinor - bp.actualTotalSpendMinor) *
              100.0 /
              actualDenom)
        : 0.0;

    return RefreshIndicator(
      onRefresh: () => _reload(profile),
      child: SingleChildScrollView(
        key: const Key('life_tab_status'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EnterprisePageContainer.responsivePadding(context, bottom: 96),
        child: EnterprisePageContainer(
          maxWidth: AppBreakpoints.maxContentWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Horizontal Trendy Life-Stage Bento Selector
              const SectionHeader(
                title: 'Choose Your Life Status',
                subtitle: 'Ratios, EMI ceiling & safety net adapt instantly',
              ),
              const SizedBox(height: AppSpacing.xs),
              SizedBox(
                height: 122,
                child: ListView.separated(
                  key: const Key('life_status_list'),
                  scrollDirection: Axis.horizontal,
                  scrollCacheExtent: const ScrollCacheExtent.pixels(640),
                  itemCount: LifeStageStatus.values.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, idx) {
                    final st = LifeStageStatus.values[idx];
                    final selected = st == t.status;
                    return _LifeStageBentoCard(
                      key: Key('life_card_${st.wireValue}'),
                      status: st,
                      selected: selected,
                      onTap: () {
                        final defaultDeps = st == LifeStageStatus.familyWithKids
                            ? math.max(1, t.dependentsCount)
                            : (st == LifeStageStatus.sandwichFamily
                                  ? math.max(2, t.dependentsCount)
                                  : (st == LifeStageStatus.bachelor ||
                                            st == LifeStageStatus.studentStarter
                                        ? 0
                                        : t.dependentsCount));
                        _updateProfilePrefs(
                          profile,
                          status: st,
                          dependentsCount: defaultDeps,
                          housingMode: t.housingMode,
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // 2. Personalize Dependents, Housing & Income Pool
              StaggeredFadeSlide(
                index: 0,
                child: PressScaleCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Dependents Row
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Dependents (Kids / Parents)',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  'Tunes Essentials % & Emergency months',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(color: cfo.subtleText),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _StepperPill(
                            count: t.dependentsCount,
                            onMinus: t.dependentsCount > 0
                                ? () => _updateProfilePrefs(
                                    profile,
                                    status: t.status,
                                    dependentsCount: t.dependentsCount - 1,
                                    housingMode: t.housingMode,
                                  )
                                : null,
                            onPlus: t.dependentsCount < 6
                                ? () => _updateProfilePrefs(
                                    profile,
                                    status: t.status,
                                    dependentsCount: t.dependentsCount + 1,
                                    housingMode: t.housingMode,
                                  )
                                : null,
                          ),
                        ],
                      ),
                      const Divider(height: 20),

                      // Housing Mode Chips
                      Text(
                        'Housing Situation',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final h in HousingMode.values)
                            _SelectablePill(
                              key: Key('life_housing_${h.wireValue}'),
                              label: h.label,
                              active: t.housingMode == h,
                              onTap: () => _updateProfilePrefs(
                                profile,
                                status: t.status,
                                dependentsCount: t.dependentsCount,
                                housingMode: h,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // 3. Bottom-Up Monthly Income & Real Commitments Sheet
              StaggeredFadeSlide(
                index: 1,
                child: BottomUpExpenseSheetCard(
                  profileId: profile.id.value,
                  targets: t,
                  expenseProfile: snap.expenseProfile,
                  trackedLoanEmiMinor: snap.cashFlowPlan.trackedLoanEmiMinor,
                  currencyCode: ccy,
                  masked: masked,
                  busy: _savingCashFlow,
                  onSaveProfile: (updated) => _saveExpenseProfile(
                    context,
                    profile,
                    updated,
                    toastMessage:
                        'CFP plan updated for your real income & expenses.',
                  ),
                  onAutoFillFromLedger: () =>
                      _autoFillFromLedger(context, profile),
                  onEstimateTypical: (primary, secondary, manualEmi) =>
                      _estimateTypicalExpenses(
                        context,
                        profile,
                        snap,
                        primary,
                        secondary,
                        manualEmi,
                      ),
                ),
              ),
              if (snap.incomePoolMinor > 0 &&
                  profile.permissions.canPostTransaction &&
                  snap.liquidAccounts.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                _SalaryBankLinkCard(
                  snap: snap,
                  masked: masked,
                  onCreditSalary: () =>
                      _openCreditSalaryDialog(context, profile, snap),
                ),
              ],
              const SizedBox(height: AppSpacing.md),

              // 4. Personalized CFP Cash-Flow Waterfall OR Ideal Paycheck Split
              if (snap.expenseProfile.hasAnyEnteredExpenses)
                StaggeredFadeSlide(
                  index: 2,
                  child: _buildBottomUpCfpPlanCard(
                    context,
                    snap: snap,
                    masked: masked,
                  ),
                )
              else
                StaggeredFadeSlide(
                  index: 2,
                  child: FintechAccentCard(
                    key: const Key('life_cfp_plan_card'),
                    accent: ModernDialogAccent.brand,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Ideal ${t.status.shortLabel} Money Split',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            FintechStatusPill(
                              label: 'Max EMI ${t.maxSafeDtiPct}%',
                              foreground: scheme.primary,
                              background: scheme.primaryContainer,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SegmentedMoneyBar(
                          segments: idealSegments,
                          masked: masked,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _MiniMoneyTile(
                                label: 'Needs (${t.needsPct}%)',
                                minor: bp.needsTargetMinor,
                                ccy: ccy,
                                masked: masked,
                                color: scheme.primary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _MiniMoneyTile(
                                label: 'Wants (${t.wantsPct}%)',
                                minor: bp.wantsTargetMinor,
                                ccy: ccy,
                                masked: masked,
                                color: cfo.warning,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _MiniMoneyTile(
                                label: 'Save (${t.savingsPct}%)',
                                minor: bp.savingsTargetMinor,
                                ccy: ccy,
                                masked: masked,
                                color: cfo.income,
                              ),
                            ),
                          ],
                        ),
                        if (bp.actualTotalSpendMinor > 0) ...[
                          const Divider(height: 22),
                          Text(
                            'Your Actual Spend Mix This Month',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: cfo.subtleText,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 6),
                          SegmentedMoneyBar(
                            height: 8,
                            masked: masked,
                            segments: [
                              MoneyBarSegment(
                                label: 'Needs',
                                percent: actualNeedsPct,
                                color: scheme.primary,
                              ),
                              MoneyBarSegment(
                                label: 'Wants',
                                percent: actualWantsPct,
                                color: cfo.warning,
                              ),
                              MoneyBarSegment(
                                label: 'Unspent',
                                percent: actualSavedPct,
                                color: cfo.income,
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 10),
                        Text(
                          'Tip: Tap "From Ledger" or "Estimate Typical" above to generate your exact 5-stage CFP Surplus Waterfall.',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: cfo.subtleText, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.md),

              // 5. Tailored Category Budget Envelopes + 1-Tap Apply
              SectionHeader(
                title: snap.expenseProfile.hasAnyEnteredExpenses
                    ? 'Your ${t.status.shortLabel} Budget Envelopes'
                    : '${t.status.shortLabel} Category Blueprint',
                subtitle: snap.expenseProfile.hasAnyEnteredExpenses
                    ? 'Built from your real expenses + guilt-free cap (auto-creates Insurance & Subscriptions)'
                    : 'Rent, groceries, bills & lifestyle auto-balanced',
              ),
              const SizedBox(height: AppSpacing.xs),

              if (bp.incomePoolMinor <= 0 &&
                  !snap.expenseProfile.hasAnyEnteredExpenses)
                PressScaleCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Text(
                    'Tap a monthly income preset above (e.g. $ccy 60000) or tap Estimate Typical to generate exact monthly budgets for ${t.status.title}.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: cfo.subtleText),
                  ),
                )
              else ...[
                PressScaleCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (snap.expenseProfile.hasAnyEnteredExpenses &&
                          snap.cashFlowPlan.budgetEnvelopes.isNotEmpty)
                        for (
                          var i = 0;
                          i < snap.cashFlowPlan.budgetEnvelopes.length;
                          i++
                        ) ...[
                          if (i > 0) Divider(height: 16, color: cfo.divider),
                          _PlannedEnvelopeRow(
                            envelope: snap.cashFlowPlan.budgetEnvelopes[i],
                            totalIncomeMinor:
                                snap.cashFlowPlan.totalIncomeMinor,
                            ccy: ccy,
                            masked: masked,
                          ),
                        ]
                      else
                        for (var i = 0; i < bp.recommendations.length; i++) ...[
                          if (i > 0) Divider(height: 16, color: cfo.divider),
                          _BlueprintCategoryRow(
                            rec: bp.recommendations[i],
                            ccy: ccy,
                            masked: masked,
                          ),
                        ],
                      if (canManage) ...[
                        const SizedBox(height: AppSpacing.md),
                        FilledButton.icon(
                          key: const Key('life_apply_budget_btn'),
                          onPressed: _applyingBudget
                              ? null
                              : () => _applyLifeStageBudget(
                                  context,
                                  profile,
                                  snap,
                                ),
                          icon: _applyingBudget
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.bolt_rounded),
                          label: Text(
                            '1-Tap Apply ${t.status.shortLabel} Budget',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BOTTOM-UP CFP CASH-FLOW WATERFALL & DEFICIT RESCUE CARD
  // ---------------------------------------------------------------------------
  Widget _buildBottomUpCfpPlanCard(
    BuildContext context, {
    required LifeStageWorkspaceSnapshot snap,
    required bool masked,
  }) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final plan = snap.cashFlowPlan;
    final ccy = snap.currencyCode;

    final accent = switch (plan.planMode) {
      'deficit_rescue' => ModernDialogAccent.danger,
      'tight_stabilize' => ModernDialogAccent.warning,
      _ => ModernDialogAccent.success,
    };
    final (
      String badgeText,
      Color badgeFg,
      Color badgeBg,
    ) = switch (plan.planMode) {
      'deficit_rescue' => (
        'Deficit Rescue Mode',
        cfo.expense,
        cfo.expenseContainer,
      ),
      'tight_stabilize' => (
        'Tight Surplus • ${plan.cashFlowScore}/100',
        cfo.warning,
        cfo.warningContainer,
      ),
      'awaiting_income' => (
        'Enter Income Above',
        scheme.primary,
        scheme.primaryContainer,
      ),
      _ => (
        'CFP Score ${plan.cashFlowScore}/100',
        cfo.income,
        cfo.incomeContainer,
      ),
    };

    final denom = math.max(
      1,
      math.max(plan.totalIncomeMinor, plan.totalCommittedOutgoMinor),
    );
    final essentialsPct = plan.totalEssentialsWithoutEmiMinor * 100.0 / denom;
    final emiPct = plan.totalEmiMinor * 100.0 / denom;
    final taxPct = plan.taxReserveMinor * 100.0 / denom;
    final savePct = plan.totalSavingsAndShieldMinor * 100.0 / denom;
    final wantsPct =
        (plan.subscriptionsMinor + plan.guiltFreeMonthlyMinor) * 100.0 / denom;

    final segments = <MoneyBarSegment>[
      if (essentialsPct > 0.4)
        MoneyBarSegment(
          label: 'Essentials',
          percent: essentialsPct,
          color: scheme.primary,
        ),
      if (emiPct > 0.4)
        MoneyBarSegment(label: 'EMIs', percent: emiPct, color: cfo.expense),
      if (taxPct > 0.4)
        MoneyBarSegment(label: 'Tax', percent: taxPct, color: cfo.accentCyan),
      if (savePct > 0.4)
        MoneyBarSegment(
          label: 'Save & Shield',
          percent: savePct,
          color: cfo.income,
        ),
      if (wantsPct > 0.4)
        MoneyBarSegment(label: 'Wants', percent: wantsPct, color: cfo.warning),
    ];

    return FintechAccentCard(
      key: const Key('life_cfp_plan_card'),
      accent: accent,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Your Personalized CFP Plan',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              FintechStatusPill(
                label: masked ? 'CFP Plan Active' : badgeText,
                showDot: true,
                foreground: badgeFg,
                background: badgeBg,
              ),
            ],
          ),
          if (segments.isNotEmpty) ...[
            const SizedBox(height: 10),
            SegmentedMoneyBar(segments: segments, masked: masked),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MiniMoneyTile(
                  label: masked
                      ? 'Committed'
                      : 'Committed (${plan.commitmentRatioPct.round()}%)',
                  minor: plan.totalCommittedOutgoMinor,
                  ccy: ccy,
                  masked: masked,
                  color: cfo.warning,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniMoneyTile(
                  label: plan.isDeficit ? 'Monthly Deficit' : 'Net Surplus',
                  minor: plan.isDeficit
                      ? plan.shortfallMinor
                      : plan.netSurplusMinor,
                  ccy: ccy,
                  masked: masked,
                  color: plan.isDeficit ? cfo.expense : cfo.income,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniMoneyTile(
                  label: plan.isDeficit ? 'Total EMIs' : 'Weekly Wants',
                  minor: plan.isDeficit
                      ? plan.totalEmiMinor
                      : plan.guiltFreeWeeklyMinor,
                  ccy: ccy,
                  masked: masked,
                  color: plan.isDeficit ? cfo.expense : scheme.primary,
                ),
              ),
            ],
          ),

          // Deficit Rescue Plan (when real expenses + EMIs exceed income)
          if (plan.isDeficit && plan.deficitRescueSteps.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              key: const Key('life_deficit_rescue_box'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cfo.expenseContainer.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: cfo.expense.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.emergency_outlined,
                        size: 18,
                        color: cfo.expense,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Deficit Rescue Action Plan',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: cfo.expense,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < plan.deficitRescueSteps.length; i++) ...[
                    if (i > 0) const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${i + 1}. ',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: cfo.expense,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        Expanded(
                          child: Text(
                            masked
                                ? 'Trim discretionary bills or boost income to close your monthly shortfall.'
                                : plan.deficitRescueSteps[i],
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: scheme.onSurface,
                                  height: 1.35,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],

          // 5-Stage CFP Surplus Allocation Waterfall
          if (!plan.isDeficit && plan.waterfallSteps.isNotEmpty) ...[
            Divider(height: 24, color: cfo.divider),
            Text(
              '5-Stage Surplus Allocation Waterfall',
              key: const Key('life_waterfall_heading'),
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              masked
                  ? 'Every unit of your monthly surplus assigned with zero remainder'
                  : '100% of your ${Money(amountMinor: plan.netSurplusMinor, currencyCode: ccy).format()} surplus assigned with zero remainder',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < plan.waterfallSteps.length; i++) ...[
              if (i > 0) Divider(height: 16, color: cfo.divider),
              _WaterfallStepRow(
                step: plan.waterfallSteps[i],
                ccy: ccy,
                masked: masked,
              ),
            ],
          ],

          // CFP Benchmark & Under-Protection Audit Alerts
          if (plan.benchmarkFlags.isNotEmpty) ...[
            Divider(height: 24, color: cfo.divider),
            Text(
              'CFP Expense & Protection Audit',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < plan.benchmarkFlags.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _BenchmarkFlagBanner(
                flag: plan.benchmarkFlags[i],
                masked: masked,
              ),
            ],
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('life_open_monthly_tracker_btn'),
              onPressed: () => context.push('/monthly'),
              icon: const Icon(Icons.calendar_month_rounded, size: 17),
              label: const Text('Track this month & bucket list'),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 1: EMI & DEBT GUARD (DTI SPEEDOMETER + AVALANCHE/SNOWBALL + AFFORDABILITY)
  // ---------------------------------------------------------------------------
  Widget _buildEmiAndDebtTab(
    BuildContext context, {
    required FinancialProfile profile,
    required LifeStageWorkspaceSnapshot snap,
    required bool masked,
  }) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final ccy = snap.currencyCode;
    final spec = CurrencyCatalog.requireByCode(ccy);
    final unit = math.pow(10, spec.minorUnit).toInt();

    final sampleLoans = <ActiveLoanSnapshot>[
      ActiveLoanSnapshot(
        loanId: 'sample-cc',
        name: 'Credit Card / Personal EMI',
        remainingPrincipalMinor: 120000 * unit,
        monthlyEmiMinor: 6500 * unit,
        annualInterestRateBps: 1800, // 18% high-interest bad debt
        remainingMonths: 24,
      ),
      ActiveLoanSnapshot(
        loanId: 'sample-car',
        name: 'Vehicle Loan',
        remainingPrincipalMinor: 350000 * unit,
        monthlyEmiMinor: 9200 * unit,
        annualInterestRateBps: 1050, // 10.5% APR
        remainingMonths: 48,
      ),
    ];

    final hasRealLoans = snap.emiHealth.loans.isNotEmpty;
    final simLoans = hasRealLoans
        ? snap.emiHealth.loans
        : (_useSampleLoans ? sampleLoans : const <ActiveLoanSnapshot>[]);

    final effectiveEmiHealth = (!hasRealLoans && _useSampleLoans)
        ? LifeStagePlannerEngine.analyzeEmiHealth(
            currencyCode: ccy,
            monthlyIncomeMinor: snap.incomePoolMinor > 0
                ? snap.incomePoolMinor
                : 60000 * unit,
            targets: snap.targets,
            loans: sampleLoans,
          )
        : snap.emiHealth;

    final maxSliderMajor = math.max(
      10000.0,
      snap.incomePoolMinor > 0
          ? ((snap.incomePoolMinor ~/ unit) * 0.25).clamp(10000.0, 50000.0)
          : 20000.0,
    );
    final clampedExtraMajor = _extraPrepayMajor.clamp(0.0, maxSliderMajor);
    final extraMinor = clampedExtraMajor.round() * unit;

    final payoff = LifeStagePlannerEngine.simulateDebtPayoff(
      loans: simLoans,
      extraMonthlyPrepaymentMinor: extraMinor,
    );
    final activeResult = _selectedStrategy == DebtPayoffStrategy.avalanche
        ? payoff.avalanche
        : payoff.snowball;

    // Live "Can I Afford This EMI?" evaluation
    final affordLoanMinor = _parseToMinor(_affordLoanCtrl.text, ccy);
    final affordRatePct = double.tryParse(_affordRateCtrl.text.trim()) ?? 10.5;
    final affordTenure = (int.tryParse(_affordTenureCtrl.text.trim()) ?? 36)
        .clamp(3, 360);
    final affordRes = LifeStagePlannerEngine.evaluateNewEmiAffordability(
      currencyCode: ccy,
      monthlyIncomeMinor: snap.incomePoolMinor,
      existingMonthlyEmiMinor: snap.emiHealth.totalMonthlyEmiMinor,
      targets: snap.targets,
      loanPrincipalMinor: affordLoanMinor,
      annualInterestRateBps: (affordRatePct * 100).round().clamp(0, 5000),
      termMonths: affordTenure,
    );

    final (Color affordColor, Color affordBg) = switch (affordRes.verdictCode) {
      'safe' => (cfo.income, cfo.incomeContainer),
      'tight' => (cfo.warning, cfo.warningContainer),
      _ => (cfo.expense, cfo.expenseContainer),
    };

    final dtiAccent = switch (effectiveEmiHealth.dtiStatus) {
      'stressed' => ModernDialogAccent.danger,
      'caution' => ModernDialogAccent.warning,
      _ => ModernDialogAccent.success,
    };

    return RefreshIndicator(
      onRefresh: () => _reload(profile),
      child: SingleChildScrollView(
        key: const Key('life_tab_emi'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EnterprisePageContainer.responsivePadding(context, bottom: 96),
        child: EnterprisePageContainer(
          maxWidth: AppBreakpoints.maxContentWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Animated Semi-Circle DTI Speedometer Hero
              StaggeredFadeSlide(
                index: 0,
                child: FintechAccentCard(
                  key: const Key('life_dti_hero_card'),
                  accent: dtiAccent,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'EMI & Debt Stress Meter',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          FintechStatusPill(
                            label: !hasRealLoans && _useSampleLoans
                                ? 'Sample Preview'
                                : switch (effectiveEmiHealth.dtiStatus) {
                                    'stressed' => 'Over EMI Limit',
                                    'caution' => 'Watch DTI',
                                    _ => 'Healthy DTI',
                                  },
                            showDot: true,
                            foreground: switch (effectiveEmiHealth.dtiStatus) {
                              'stressed' => cfo.expense,
                              'caution' => cfo.warning,
                              _ => cfo.income,
                            },
                            background: switch (effectiveEmiHealth.dtiStatus) {
                              'stressed' => cfo.expenseContainer,
                              'caution' => cfo.warningContainer,
                              _ => cfo.incomeContainer,
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SemiCircleDtiGauge(
                        dtiPercent: effectiveEmiHealth.dtiPercent,
                        maxSafeDtiPct: effectiveEmiHealth.maxSafeDtiPct,
                        dtiStatus: effectiveEmiHealth.dtiStatus,
                        masked: masked,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        effectiveEmiHealth.verdict,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cfo.subtleText,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _MiniMoneyTile(
                              label: 'Monthly EMIs',
                              minor: effectiveEmiHealth.totalMonthlyEmiMinor,
                              ccy: ccy,
                              masked: masked,
                              color: cfo.expense,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _MiniMoneyTile(
                              label: 'Safe Ceiling',
                              minor: effectiveEmiHealth.safeEmiCeilingMinor,
                              ccy: ccy,
                              masked: masked,
                              color: scheme.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _MiniMoneyTile(
                              label: 'Safe Headroom',
                              minor: effectiveEmiHealth
                                  .availableNewEmiHeadroomMinor,
                              ccy: ccy,
                              masked: masked,
                              color: cfo.income,
                            ),
                          ),
                        ],
                      ),
                      if (snap.cashFlowPlan.manualEmiMinor > 0 &&
                          !(!hasRealLoans && _useSampleLoans)) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Combined EMIs: ${Money(amountMinor: snap.cashFlowPlan.trackedLoanEmiMinor, currencyCode: ccy).format(mask: masked)} tracked loans + ${Money(amountMinor: snap.cashFlowPlan.manualEmiMinor, currencyCode: ccy).format(mask: masked)} other EMIs.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: cfo.subtleText),
                        ),
                      ],
                      if (effectiveEmiHealth.hasHighInterestDebt) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: cfo.expenseContainer,
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusMd,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 18,
                                color: cfo.expense,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'High-Interest Debt Alert: ${effectiveEmiHealth.highInterestLoans.first.name} (${effectiveEmiHealth.highInterestLoans.first.annualRatePercent.toStringAsFixed(1)}% APR). Prepay this first!',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: cfo.expense,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // 2. Interactive Debt Avalanche vs. Snowball Prepayment Simulator
              const SectionHeader(
                title: 'Debt Freedom Simulator',
                subtitle: 'Compare Avalanche vs. Snowball + extra prepayments',
              ),
              const SizedBox(height: AppSpacing.xs),
              StaggeredFadeSlide(
                index: 1,
                child: PressScaleCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!hasRealLoans) ...[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              _useSampleLoans
                                  ? 'Simulating 2 sample loans'
                                  : 'No active loans tracked yet',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                FilledButton.tonal(
                                  key: const Key('life_sample_loans_toggle'),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(0, 34),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                  ),
                                  onPressed: () {
                                    HapticFeedback.selectionClick();
                                    setState(
                                      () => _useSampleLoans = !_useSampleLoans,
                                    );
                                  },
                                  child: Text(
                                    _useSampleLoans
                                        ? 'Hide Sample'
                                        : 'Try Sample Loans',
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => context.push('/loans'),
                                  child: const Text('Add Loan'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                      if (simLoans.isNotEmpty) ...[
                        if (!hasRealLoans) const SizedBox(height: 10),
                        FintechSegmentedControl<DebtPayoffStrategy>(
                          key: const Key('life_debt_strategy_tabs'),
                          selected: _selectedStrategy,
                          options: const [
                            FintechSegmentOption(
                              value: DebtPayoffStrategy.avalanche,
                              label: 'Avalanche (Min Interest)',
                            ),
                            FintechSegmentOption(
                              value: DebtPayoffStrategy.snowball,
                              label: 'Snowball (Fast Wins)',
                            ),
                          ],
                          onChanged: (s) =>
                              setState(() => _selectedStrategy = s),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Extra Monthly Prepayment',
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              Money(
                                amountMinor: extraMinor,
                                currencyCode: ccy,
                              ).format(mask: masked),
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w900,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                            ),
                          ],
                        ),
                        if (snap.cashFlowPlan.recommendedPrepayMinor > 0) ...[
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: _SelectablePill(
                              key: const Key('life_use_cfp_prepay_btn'),
                              label:
                                  'Use CFP Waterfall Prepay (${Money(amountMinor: snap.cashFlowPlan.recommendedPrepayMinor, currencyCode: ccy).format(mask: masked)}/mo)',
                              active:
                                  (extraMinor -
                                          snap
                                              .cashFlowPlan
                                              .recommendedPrepayMinor)
                                      .abs() <
                                  unit * 250,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                final targetMajor =
                                    snap.cashFlowPlan.recommendedPrepayMinor /
                                    unit;
                                setState(
                                  () => _extraPrepayMajor = targetMajor.clamp(
                                    0.0,
                                    maxSliderMajor,
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                        Slider(
                          key: const Key('life_prepay_slider'),
                          value: clampedExtraMajor,
                          min: 0,
                          max: maxSliderMajor,
                          divisions: 20,
                          onChanged: (v) =>
                              setState(() => _extraPrepayMajor = v),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: _StatPillBox(
                                label: 'Debt-Free In',
                                value: '${activeResult.monthsToDebtFree} mo',
                                color: scheme.primary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _StatPillBox(
                                label: 'Months Saved',
                                value:
                                    '${activeResult.monthsSavedVsBaseline} mo',
                                color: cfo.income,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _MiniMoneyTile(
                                label: 'Interest Saved',
                                minor:
                                    activeResult.interestSavedVsBaselineMinor,
                                ccy: ccy,
                                masked: masked,
                                color: cfo.income,
                              ),
                            ),
                          ],
                        ),
                        if (activeResult.payoffOrderNames.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Priority Order: ${activeResult.payoffOrderNames.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('  →  ')}',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: cfo.subtleText,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // 3. "Can I Afford This New EMI?" Quick Guard Calculator
              const SectionHeader(
                title: 'Can I Afford a New EMI?',
                subtitle: 'Stress-test any loan before signing',
              ),
              const SizedBox(height: AppSpacing.xs),
              StaggeredFadeSlide(
                index: 2,
                child: PressScaleCard(
                  key: const Key('life_emi_afford_card'),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FintechTextField(
                        key: const Key('life_afford_loan_field'),
                        label: 'Prospective Loan Amount ($ccy)',
                        controller: _affordLoanCtrl,
                        compact: true,
                        leadingIcon: Icons.request_quote_outlined,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: FintechTextField(
                              label: 'Interest % (APR)',
                              controller: _affordRateCtrl,
                              compact: true,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FintechTextField(
                              label: 'Tenure (Months)',
                              controller: _affordTenureCtrl,
                              compact: true,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _SelectablePill(
                            label: 'Phone / Bike (1.5L • 24m)',
                            active: _affordLoanCtrl.text.trim() == '150000',
                            onTap: () => setState(() {
                              _affordLoanCtrl.text = '150000';
                              _affordRateCtrl.text = '12.0';
                              _affordTenureCtrl.text = '24';
                            }),
                          ),
                          _SelectablePill(
                            label: 'Car (6L • 60m)',
                            active: _affordLoanCtrl.text.trim() == '600000',
                            onTap: () => setState(() {
                              _affordLoanCtrl.text = '600000';
                              _affordRateCtrl.text = '9.5';
                              _affordTenureCtrl.text = '60';
                            }),
                          ),
                          _SelectablePill(
                            label: 'Home (35L • 240m)',
                            active: _affordLoanCtrl.text.trim() == '3500000',
                            onTap: () => setState(() {
                              _affordLoanCtrl.text = '3500000';
                              _affordRateCtrl.text = '8.7';
                              _affordTenureCtrl.text = '240';
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: affordBg,
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusMd,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  affordRes.headline,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        color: affordColor,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                Text(
                                  'Est. EMI: ${Money(amountMinor: affordRes.estimatedNewEmiMinor, currencyCode: ccy).format(mask: masked)}/mo',
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        color: affordColor,
                                        fontWeight: FontWeight.w800,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              affordRes.detail,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: affordColor.withValues(alpha: 0.92),
                                    height: 1.35,
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
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 2: SAVE & PROTECT (EMERGENCY SHIELD + CHECKLIST + PLAYBOOK)
  // ---------------------------------------------------------------------------
  Widget _buildSaveAndProtectTab(
    BuildContext context, {
    required FinancialProfile profile,
    required LifeStageWorkspaceSnapshot snap,
    required bool masked,
    required bool canManage,
  }) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final sh = snap.shield;
    final ccy = snap.currencyCode;
    final shieldColor = sh.isFullyFunded
        ? cfo.income
        : (sh.shieldScore >= 50 ? cfo.warning : cfo.expense);

    return RefreshIndicator(
      onRefresh: () => _reload(profile),
      child: SingleChildScrollView(
        key: const Key('life_tab_save'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EnterprisePageContainer.responsivePadding(context, bottom: 96),
        child: EnterprisePageContainer(
          maxWidth: AppBreakpoints.maxContentWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Essential-Outgo Emergency Fund Shield Hero
              StaggeredFadeSlide(
                index: 0,
                child: FintechAccentCard(
                  key: const Key('life_emergency_shield_card'),
                  accent: sh.isFullyFunded
                      ? ModernDialogAccent.success
                      : ModernDialogAccent.brand,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          RadialScoreGauge(
                            score: masked ? 0 : sh.shieldScore,
                            label: masked ? '••%' : '${sh.shieldScore}%',
                            activeColor: shieldColor,
                            secondaryColor: cfo.accentCyan,
                            size: 82,
                            strokeWidth: 7,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${sh.targetMonths}-Month Emergency Shield',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  masked
                                      ? 'Covered: •• / ${sh.targetMonths} mo'
                                      : '${sh.coveredMonths.toStringAsFixed(1)} of ${sh.targetMonths} essential months covered',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: shieldColor,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  snap.expenseProfile.hasAnyEnteredExpenses
                                      ? 'Based on your real ${Money(amountMinor: snap.cashFlowPlan.essentialOutgoForShieldMinor, currencyCode: ccy).format(mask: masked)}/mo essential outgo (Rent, Groceries, Fees, Insurance, Bills & EMIs).'
                                      : 'Based on Essential Outgo (Needs + EMIs), not gross salary.',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(color: cfo.subtleText),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _MiniMoneyTile(
                              label: 'Target Corpus',
                              minor: sh.targetCorpusMinor,
                              ccy: ccy,
                              masked: masked,
                              color: scheme.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _MiniMoneyTile(
                              label: 'Liquid Cash',
                              minor: sh.liquidCashMinor,
                              ccy: ccy,
                              masked: masked,
                              color: cfo.income,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _MiniMoneyTile(
                              label: '12-Mo Bridge',
                              minor: sh.monthlyBridgeSavingMinor,
                              ccy: ccy,
                              masked: masked,
                              color: cfo.warning,
                            ),
                          ),
                        ],
                      ),
                      if (canManage) ...[
                        const SizedBox(height: 12),
                        if (snap.hasEmergencyGoalAlready)
                          FilledButton.tonalIcon(
                            onPressed: () => context.push('/goals'),
                            icon: const Icon(Icons.verified_outlined, size: 18),
                            label: const Text(
                              'Emergency Goal Active — View Goals',
                            ),
                          )
                        else
                          FilledButton.icon(
                            key: const Key('life_create_emergency_goal_btn'),
                            onPressed: _creatingGoal
                                ? null
                                : () => _createEmergencyGoal(
                                    context,
                                    profile,
                                    snap,
                                  ),
                            icon: _creatingGoal
                                ? const SizedBox(
                                    width: 15,
                                    height: 15,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.shield_rounded, size: 18),
                            label: Text(
                              '1-Tap Create ${sh.targetMonths}-Month Emergency Goal',
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // 2. Protection & Insurance Essentials Checklist
              SectionHeader(
                title: '${snap.targets.status.shortLabel} Safety Checklist',
                subtitle: 'Non-negotiable financial shields for your stage',
              ),
              const SizedBox(height: AppSpacing.xs),
              StaggeredFadeSlide(
                index: 1,
                child: PressScaleCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    children: [
                      for (
                        var i = 0;
                        i < snap.protectionChecklist.length;
                        i++
                      ) ...[
                        if (i > 0) Divider(height: 18, color: cfo.divider),
                        _ProtectionItemRow(item: snap.protectionChecklist[i]),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // 3. Numbered "How to Save & Manage Money" Playbook
              const SectionHeader(
                title: 'How to Save & Manage Money',
                subtitle: 'Personalized rules for your status & EMI load',
              ),
              const SizedBox(height: AppSpacing.xs),
              StaggeredFadeSlide(
                index: 2,
                child: PressScaleCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    children: [
                      for (var i = 0; i < snap.playbook.length; i++) ...[
                        if (i > 0) Divider(height: 18, color: cfo.divider),
                        _PlaybookTipRow(index: i + 1, tip: snap.playbook[i]),
                      ],
                    ],
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

class _LifeStageBentoCard extends StatelessWidget {
  const _LifeStageBentoCard({
    required this.status,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final LifeStageStatus status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primaryContainer.withValues(alpha: 0.55)
          : cfo.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        side: BorderSide(
          color: selected ? scheme.primary : cfo.divider,
          width: selected ? 1.8 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        onTap: onTap,
        child: Container(
          width: 176,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconSquircle(
                    icon: lifeStageIcon(status),
                    iconColor: selected ? scheme.onPrimary : scheme.primary,
                    backgroundColor: selected
                        ? scheme.primary
                        : scheme.primaryContainer,
                    size: 30,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      status.shortLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: selected ? scheme.primary : null,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Text(
                  status.tagline,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cfo.subtleText,
                    height: 1.25,
                  ),
                ),
              ),
              Text(
                status.ratioBadge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepperPill extends StatelessWidget {
  const _StepperPill({required this.count, this.onMinus, this.onPlus});

  final int count;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cfo.surfaceTonal,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(color: cfo.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const Key('life_deps_minus'),
            visualDensity: VisualDensity.compact,
            onPressed: onMinus,
            icon: const Icon(Icons.remove_rounded, size: 18),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '$count',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: scheme.primary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          IconButton(
            key: const Key('life_deps_plus'),
            visualDensity: VisualDensity.compact,
            onPressed: onPlus,
            icon: const Icon(Icons.add_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

class _SelectablePill extends StatelessWidget {
  const _SelectablePill({
    required this.label,
    required this.active,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: active ? scheme.primaryContainer : cfo.surfaceTonal,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        side: BorderSide(color: active ? scheme.primary : cfo.divider),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: active ? scheme.primary : cfo.subtleText,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniMoneyTile extends StatelessWidget {
  const _MiniMoneyTile({
    required this.label,
    required this.minor,
    required this.ccy,
    required this.masked,
    required this.color,
  });

  final String label;
  final int minor;
  final String ccy;
  final bool masked;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cfo.surfaceTonal,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MoneyText(
              money: Money(amountMinor: minor, currencyCode: ccy),
              masked: masked,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatPillBox extends StatelessWidget {
  const _StatPillBox({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cfo.surfaceTonal,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlueprintCategoryRow extends StatelessWidget {
  const _BlueprintCategoryRow({
    required this.rec,
    required this.ccy,
    required this.masked,
  });

  final LifeStageCategoryRecommendation rec;
  final String ccy;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final isNeed = rec.bucketLabel == 'Essential Need';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    rec.categoryName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  FintechStatusPill(
                    label: isNeed ? 'Need' : 'Want',
                    foreground: isNeed ? scheme.primary : cfo.warning,
                    background: isNeed
                        ? scheme.primaryContainer
                        : cfo.warningContainer,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                rec.actualSpendMinor > 0
                    ? 'Actual this month: ${Money(amountMinor: rec.actualSpendMinor, currencyCode: ccy).format(mask: masked)}'
                    : (masked
                          ? '••% of income'
                          : '${rec.shareOfIncomePercent.round()}% of monthly income'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: rec.isOverRecommended ? cfo.expense : cfo.subtleText,
                  fontWeight: rec.isOverRecommended
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 118),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: MoneyText(
              money: Money(
                amountMinor: rec.recommendedLimitMinor,
                currencyCode: ccy,
              ),
              masked: masked,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProtectionItemRow extends StatelessWidget {
  const _ProtectionItemRow({required this.item});
  final ProtectionCheckItem item;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconSquircle(
          icon: Icons.verified_user_outlined,
          iconColor: cfo.income,
          backgroundColor: cfo.incomeContainer,
          size: 32,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  FintechStatusPill(
                    label: item.priorityBadge,
                    foreground: scheme.primary,
                    background: scheme.primaryContainer,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                item.subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cfo.subtleText,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlaybookTipRow extends StatelessWidget {
  const _PlaybookTipRow({required this.index, required this.tip});
  final int index;
  final LifeStageActionTip tip;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$index',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    tip.title,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  FintechStatusPill(
                    label: tip.tag,
                    foreground: cfo.income,
                    background: cfo.incomeContainer,
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                tip.detail,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cfo.subtleText,
                  height: 1.38,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WaterfallStepRow extends StatelessWidget {
  const _WaterfallStepRow({
    required this.step,
    required this.ccy,
    required this.masked,
  });

  final SurplusWaterfallStep step;
  final String ccy;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;

    final (Color fg, Color bg) = switch (step.code) {
      'emergency' => (cfo.income, cfo.incomeContainer),
      'emi_prepay' => (cfo.expense, cfo.expenseContainer),
      'sinking' => (cfo.warning, cfo.warningContainer),
      'wealth_sip' => (scheme.primary, scheme.primaryContainer),
      _ => (cfo.accentCyan, cfo.surfaceTonal),
    };

    final safeSubtitle = masked
        ? switch (step.code) {
            'emergency' =>
              'Builds your essential-outgo emergency buffer automatically.',
            'emi_prepay' =>
              'Accelerates highest-APR debt payoff to cut total interest.',
            'sinking' =>
              'Pre-funds lumpy annual school fees, renewals & travel.',
            'wealth_sip' =>
              'Automate on Salary Day 1 so long-term wealth compounds first.',
            _ => 'Weekly pocket cap: •••••• for dining, outings & shopping.',
          }
        : step.subtitle;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Text(
            '${step.stageNumber}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    step.title,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (!masked)
                    FintechStatusPill(
                      label: '${step.percentOfIncome.round()}% inc',
                      foreground: fg,
                      background: bg,
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                safeSubtitle,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cfo.subtleText,
                  height: 1.35,
                ),
              ),
              if (step.weeklyAllowanceMinor != null &&
                  step.weeklyAllowanceMinor! > 0) ...[
                const SizedBox(height: 5),
                FintechStatusPill(
                  label:
                      'Weekly Cap: ${Money(amountMinor: step.weeklyAllowanceMinor!, currencyCode: ccy).format(mask: masked)}/wk',
                  foreground: scheme.primary,
                  background: scheme.primaryContainer,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 114),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: MoneyText(
              money: Money(amountMinor: step.amountMinor, currencyCode: ccy),
              masked: masked,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: fg,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BenchmarkFlagBanner extends StatelessWidget {
  const _BenchmarkFlagBanner({required this.flag, required this.masked});

  final ExpenseBenchmarkFlag flag;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final isDanger = flag.severity == 'danger';
    final fg = isDanger ? cfo.expense : cfo.warning;
    final bg = isDanger ? cfo.expenseContainer : cfo.warningContainer;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: fg.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isDanger
                ? Icons.gpp_maybe_outlined
                : Icons.tips_and_updates_outlined,
            size: 18,
            color: fg,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  masked ? 'CFP Alert Flagged' : flag.title,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  masked
                      ? 'Disable balance masking to inspect exact benchmark figures.'
                      : flag.detail,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlannedEnvelopeRow extends StatelessWidget {
  const _PlannedEnvelopeRow({
    required this.envelope,
    required this.totalIncomeMinor,
    required this.ccy,
    required this.masked,
  });

  final PlannedCategoryEnvelope envelope;
  final int totalIncomeMinor;
  final String ccy;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final isWant =
        envelope.tierLabel.contains('Want') ||
        envelope.tierLabel.contains('Guilt');
    final isProtection = envelope.tierLabel == 'Protection';
    final (Color fg, Color bg) = isProtection
        ? (cfo.income, cfo.incomeContainer)
        : (isWant
              ? (cfo.warning, cfo.warningContainer)
              : (scheme.primary, scheme.primaryContainer));
    final sharePct = totalIncomeMinor > 0
        ? (envelope.amountMinor * 100.0 / totalIncomeMinor).round()
        : 0;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    envelope.categoryName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  FintechStatusPill(
                    label: envelope.tierLabel,
                    foreground: fg,
                    background: bg,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                masked
                    ? '••% of monthly income'
                    : '$sharePct% of monthly income',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 118),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: MoneyText(
              money: Money(
                amountMinor: envelope.amountMinor,
                currencyCode: ccy,
              ),
              masked: masked,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SalaryBankLinkCard extends StatelessWidget {
  const _SalaryBankLinkCard({
    required this.snap,
    required this.masked,
    required this.onCreditSalary,
  });

  final LifeStageWorkspaceSnapshot snap;
  final bool masked;
  final VoidCallback onCreditSalary;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final credited = snap.salaryCreditedThisMonth;
    final linkedAcc = snap.liquidAccounts
        .where((a) => a.id == snap.salaryAccountId)
        .firstOrNull;
    final accLabel = linkedAcc?.name ?? snap.liquidAccounts.first.name;
    final plannedMoney = Money(
      amountMinor: snap.incomePoolMinor,
      currencyCode: snap.currencyCode,
    );
    final actualMoney = Money(
      amountMinor: snap.currentMonthActualIncomeMinor,
      currencyCode: snap.currencyCode,
    );

    return FintechAccentCard(
      key: const Key('life_salary_bank_card'),
      accent: credited ? ModernDialogAccent.success : ModernDialogAccent.brand,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconSquircle(
                icon: credited
                    ? Icons.verified_rounded
                    : Icons.account_balance_outlined,
                iconColor: credited ? cfo.income : scheme.primary,
                backgroundColor: credited
                    ? cfo.incomeContainer
                    : scheme.primaryContainer,
                size: 38,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          credited
                              ? 'Salary Credited to Bank'
                              : 'Credit Salary to Account',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        FintechStatusPill(
                          label: credited ? 'Credited' : 'Planned only',
                          foreground: credited ? cfo.income : cfo.warning,
                          background: credited
                              ? cfo.incomeContainer
                              : cfo.warningContainer,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      credited
                          ? '${actualMoney.format(mask: masked)} logged this month • Linked: $accLabel'
                          : 'Planned ${plannedMoney.format(mask: masked)} stays an estimate until deposited into $accLabel.',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cfo.subtleText,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: credited
                ? TextButton.icon(
                    key: const Key('life_credit_salary_btn'),
                    onPressed: onCreditSalary,
                    icon: const Icon(
                      Icons.add_circle_outline_rounded,
                      size: 16,
                    ),
                    label: const Text('Credit Extra'),
                  )
                : FilledButton.tonalIcon(
                    key: const Key('life_credit_salary_btn'),
                    onPressed: onCreditSalary,
                    icon: const Icon(Icons.payments_outlined, size: 16),
                    label: const Text('Credit to Bank'),
                  ),
          ),
        ],
      ),
    );
  }
}
