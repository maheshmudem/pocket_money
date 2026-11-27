import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/financial_engine/cfo_advisor_engine.dart';
import '../../../../core/financial_engine/money.dart';
import '../../../../shared/widgets/classic_motion.dart';
import '../../../../shared/widgets/enterprise_layout.dart';
import '../../../../shared/widgets/fintech_widgets.dart';
import '../../../../shared/widgets/modern_dialogs.dart';
import '../../../../shared/widgets/modern_inputs.dart';
import '../../../budgets/domain/entities/budget_entity.dart';
import '../../../budgets/domain/repositories/budget_repository.dart';
import '../../../dashboard/presentation/bloc/dashboard_bloc.dart';
import '../../../profiles/domain/entities/profile_entity.dart';
import '../../../profiles/presentation/bloc/active_profile_cubit.dart';
import '../../../settings/presentation/bloc/settings_cubit.dart';
import '../../../transactions/domain/entities/transaction_entity.dart';
import '../../../transactions/presentation/pages/transactions_page.dart';
import '../../data/cfo_advisor_service.dart';

class _ChatMessage {
  const _ChatMessage.user(this.text) : isUser = true, reply = null;
  const _ChatMessage.coach(this.reply) : isUser = false, text = null;

  final bool isUser;
  final String? text;
  final CoachReply? reply;
}

/// `SCR-AI-001` — 100% Free, Offline, On-Device Smart CFO Advisor & Budget Coach.
///
/// Combines Month-by-Month Spend Audit, Adaptive 50/30/20 & WMA Budget Planner
/// with 1-Tap Apply, and an Interactive Offline Financial Q&A Coach.
class AiCoachPage extends StatefulWidget {
  const AiCoachPage({super.key, this.initialTab = 0});

  /// `0` = Monthly Audit, `1` = Smart Budget Plan, `2` = Ask CFO Coach.
  final int initialTab;

  @override
  State<AiCoachPage> createState() => _AiCoachPageState();
}

class _AiCoachPageState extends State<AiCoachPage> {
  late int _activeTab;
  CfoAdvisorReport? _report;
  String? _selectedYearMonth;
  bool _loading = true;
  bool _applyingBudget = false;
  String? _loadedProfileId;

  final _chatCtrl = TextEditingController();
  final _chatScrollCtrl = ScrollController();
  final List<_ChatMessage> _messages = [];

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab.clamp(0, 2);
  }

  @override
  void dispose() {
    _chatCtrl.dispose();
    _chatScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload(
    FinancialProfile profile, {
    String? yearMonth,
    bool resetChat = false,
  }) async {
    _loadedProfileId = profile.id.value;
    setState(() => _loading = true);
    final res = await GetIt.I<CfoAdvisorService>().buildReport(
      profileId: profile.id,
      baseCurrencyCode: profile.baseCurrencyCode,
      selectedYearMonth: yearMonth ?? _selectedYearMonth,
    );
    if (!mounted) return;
    final report = res.valueOrNull;
    final masked = context.read<SettingsCubit>().state.hideBalances;
    setState(() {
      _report = report;
      _selectedYearMonth = report?.selectedYearMonth;
      _loading = false;
      if (report != null && (resetChat || _messages.isEmpty)) {
        _messages
          ..clear()
          ..add(
            _ChatMessage.coach(
              CfoAdvisorEngine.answerQuestion(
                report,
                'Where is my money going this month?',
                maskBalances: masked,
              ),
            ),
          );
      }
    });
  }

  Future<void> _applyBudgetAction(
    BuildContext context,
    FinancialProfile profile,
    CoachBudgetAction action,
  ) async {
    if (!profile.permissions.canManageCategoriesAndBudgets || _applyingBudget) {
      return;
    }
    final formatted = Money(
      amountMinor: action.limitMinor,
      currencyCode: profile.baseCurrencyCode,
    ).format();
    final confirmed = await showModernConfirmDialog(
      context: context,
      title: 'Apply Suggested Budget?',
      subtitle: action.categoryName != null
          ? 'Monthly category cap for ${action.categoryName}'
          : 'Overall monthly spending guard',
      icon: Icons.auto_awesome_rounded,
      accent: ModernDialogAccent.success,
      confirmLabel: 'Apply $formatted',
      message:
          'Create "${action.name}" with a monthly limit of $formatted? Pocket CFO will alert you at 80% and 100% automatically.',
    );
    if (confirmed != true || !context.mounted) return;

    setState(() => _applyingBudget = true);
    try {
      final res = await GetIt.I<BudgetRepository>().createBudget(
        profileId: profile.id,
        name: action.name,
        periodType: BudgetPeriodType.monthly,
        overallLimitMinor: action.limitMinor,
        currencyCode: profile.baseCurrencyCode,
        categoryLimitsMinor: action.categoryId != null
            ? {action.categoryId!: action.limitMinor}
            : const {},
        rolloverEnabled: false,
      );
      if (!context.mounted) return;
      if (res.isSuccess) {
        context.read<DashboardBloc?>()?.add(const DashboardRefreshRequested());
        showFintechToast(
          context,
          'Applied "${action.name}" ($formatted/month).',
          tone: FintechToastTone.success,
        );
        await _reload(profile, yearMonth: _selectedYearMonth);
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

  void _sendQuestion(String rawText) {
    final report = _report;
    final text = rawText.trim();
    if (report == null || text.isEmpty) return;
    HapticFeedback.selectionClick();
    final masked = context.read<SettingsCubit>().state.hideBalances;
    final reply = CfoAdvisorEngine.answerQuestion(
      report,
      text,
      maskBalances: masked,
    );
    setState(() {
      _messages.add(_ChatMessage.user(text));
      _messages.add(_ChatMessage.coach(reply));
      _chatCtrl.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollCtrl.hasClients) {
        _chatScrollCtrl.animateTo(
          _chatScrollCtrl.position.maxScrollExtent,
          duration: AppMotion.resolve(context, AppMotion.standard),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ActiveProfileCubit>().state.activeProfile;
    final hideBalances = context.watch<SettingsCubit>().state.hideBalances;
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;

    if (profile == null) {
      return const Scaffold(
        body: EmptyStateView(
          icon: Icons.auto_awesome_rounded,
          title: 'No active profile',
          description: 'Select a profile to run on-device CFO coaching.',
        ),
      );
    }

    if (_loadedProfileId != profile.id.value) {
      _loadedProfileId = profile.id.value;
      _selectedYearMonth = null;
      Future.microtask(() => _reload(profile, resetChat: true));
    }

    final report = _report;
    final canManageBudgets = profile.permissions.canManageCategoriesAndBudgets;
    final canPost = profile.permissions.canPostTransaction;

    return Scaffold(
      appBar: EnterpriseAppBar(
        title: const Text('Smart CFO Coach'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: FintechStatusPill(
                label: 'FREE LOCAL AI',
                showDot: true,
                foreground: cfo.income,
                background: cfo.incomeContainer,
              ),
            ),
          ),
        ],
      ),
      body: ClassicContentSwitcher(
        stateKey: _loading && report == null
            ? 'loading'
            : report == null
            ? 'empty'
            : 'loaded',
        child: _loading && report == null
            ? const DashboardSkeletonView()
            : report == null
            ? EmptyStateView(
                icon: Icons.auto_awesome_outlined,
                title: 'Unable to load advisor',
                description: 'Pull down or tap retry to analyze your ledger.',
                actionLabel: 'Retry',
                onAction: () => _reload(profile),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top segmented mode bar + month strip
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FintechSegmentedControl<int>(
                            key: const Key('coach_segmented_tabs'),
                            selected: _activeTab,
                            options: const [
                              FintechSegmentOption(
                                value: 0,
                                label: 'Monthly Audit',
                                icon: Icons.analytics_outlined,
                              ),
                              FintechSegmentOption(
                                value: 1,
                                label: 'Budget Plan',
                                icon: Icons.pie_chart_outline_rounded,
                              ),
                              FintechSegmentOption(
                                value: 2,
                                label: 'Ask Coach',
                                icon: Icons.auto_awesome_rounded,
                              ),
                            ],
                            onChanged: (idx) {
                              ScaffoldMessenger.of(
                                context,
                              ).hideCurrentSnackBar();
                              setState(() => _activeTab = idx);
                            },
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            key: const Key('coach_month_strip'),
                            height: 34,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: report.availableMonths.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 6),
                              itemBuilder: (context, idx) {
                                final m = report.availableMonths[idx];
                                final active =
                                    m.yearMonth == report.selectedYearMonth;
                                final hasSpend = m.totalSpendMinor > 0;
                                return AnimatedContainer(
                                  duration: AppMotion.resolve(
                                    context,
                                    AppMotion.fast,
                                  ),
                                  curve: AppMotion.curveStandard,
                                  decoration: BoxDecoration(
                                    color: active
                                        ? scheme.primaryContainer
                                        : cfo.surfaceTonal,
                                    borderRadius: BorderRadius.circular(
                                      AppSpacing.radiusFull,
                                    ),
                                    border: Border.all(
                                      color: active
                                          ? scheme.primary
                                          : cfo.divider,
                                    ),
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        AppSpacing.radiusFull,
                                      ),
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(
                                        AppSpacing.radiusFull,
                                      ),
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        _reload(
                                          profile,
                                          yearMonth: m.yearMonth,
                                          resetChat: true,
                                        );
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 11,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (hasSpend) ...[
                                              Container(
                                                width: 6,
                                                height: 6,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: active
                                                      ? scheme.primary
                                                      : cfo.income,
                                                ),
                                              ),
                                              const SizedBox(width: 5),
                                            ],
                                            Text(
                                              m.shortLabel,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall
                                                  ?.copyWith(
                                                    color: active
                                                        ? scheme
                                                              .onPrimaryContainer
                                                        : cfo.subtleText,
                                                    fontWeight: active
                                                        ? FontWeight.w800
                                                        : FontWeight.w600,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Divider(height: 1, color: cfo.divider),
                  Expanded(
                    child: ClassicTabSwitcher(
                      activeIndex: _activeTab,
                      child: switch (_activeTab) {
                        0 => _buildMonthlyAuditTab(
                          context,
                          profile,
                          report,
                          hideBalances,
                          canManageBudgets,
                          canPost,
                        ),
                        1 => _buildBudgetPlanTab(
                          context,
                          profile,
                          report,
                          hideBalances,
                          canManageBudgets,
                        ),
                        _ => _buildAskCoachTab(
                          context,
                          profile,
                          report,
                          hideBalances,
                          canManageBudgets,
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
  // TAB 0: MONTHLY AUDIT ("WHERE MONEY GOES")
  // ---------------------------------------------------------------------------
  Widget _buildMonthlyAuditTab(
    BuildContext context,
    FinancialProfile profile,
    CfoAdvisorReport report,
    bool masked,
    bool canManageBudgets,
    bool canPost,
  ) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final ccy = report.currencyCode;

    final (
      ModernDialogAccent accent,
      Color statusFg,
      Color statusBg,
      String statusLabel,
    ) = switch (report.paceStatus) {
      'overspending' => (
        ModernDialogAccent.danger,
        cfo.expense,
        cfo.expenseContainer,
        'Over Pace',
      ),
      'watch' => (
        ModernDialogAccent.warning,
        cfo.warning,
        cfo.warningContainer,
        'Watch Pace',
      ),
      'on_track' => (
        ModernDialogAccent.success,
        cfo.income,
        cfo.incomeContainer,
        'On Track',
      ),
      _ => (
        ModernDialogAccent.brand,
        cfo.subtleText,
        cfo.surfaceTonal,
        'No Spend Yet',
      ),
    };

    return RefreshIndicator(
      onRefresh: () => _reload(profile, yearMonth: report.selectedYearMonth),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EnterprisePageContainer.responsivePadding(context, bottom: 40),
        child: EnterprisePageContainer(
          maxWidth: AppBreakpoints.maxContentWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Hero Monthly Spend & Pace Forecast Card
              StaggeredFadeSlide(
                index: 0,
                child: FintechAccentCard(
                  accent: accent,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${report.selectedMonthLabel} Spend',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        color: cfo.subtleText,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const SizedBox(height: 3),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: MoneyText(
                                    money: Money(
                                      amountMinor: report.monthSpendMinor,
                                      currencyCode: ccy,
                                    ),
                                    masked: masked,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          FintechStatusPill(
                            label: statusLabel,
                            showDot: true,
                            foreground: statusFg,
                            background: statusBg,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _CompactKpiTile(
                              label: 'Income',
                              value: Money(
                                amountMinor: report.monthIncomeMinor,
                                currencyCode: ccy,
                              ).format(mask: masked),
                              color: cfo.income,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _CompactKpiTile(
                              label: 'Avg / Day',
                              value: Money(
                                amountMinor: report.dailyAverageSpendMinor,
                                currencyCode: ccy,
                              ).format(mask: masked),
                              color: scheme.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _CompactKpiTile(
                              label: report.isCurrentMonth
                                  ? 'Projected'
                                  : 'vs Prior Mo',
                              value: report.isCurrentMonth
                                  ? Money(
                                      amountMinor:
                                          report.projectedMonthEndSpendMinor,
                                      currencyCode: ccy,
                                    ).format(mask: masked)
                                  : (report.momSpendDeltaPercent == null
                                        ? '—'
                                        : '${report.momSpendDeltaPercent! >= 0 ? '+' : ''}${report.momSpendDeltaPercent!.round()}%'),
                              color: report.paceStatus == 'overspending'
                                  ? cfo.expense
                                  : cfo.subtleText,
                            ),
                          ),
                        ],
                      ),
                      if (report.momSpendDeltaPercent != null && !masked) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${report.momSpendDeltaPercent! >= 0 ? 'Up +' : 'Down '}${report.momSpendDeltaPercent!.abs().round()}% compared to last month (${Money(amountMinor: report.previousMonthSpendMinor, currencyCode: ccy).format()})',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: cfo.subtleText),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              if (!report.hasActivity) ...[
                const SizedBox(height: AppSpacing.md),
                PressScaleCard(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    children: [
                      IconSquircle(
                        icon: Icons.insights_rounded,
                        iconColor: scheme.primary,
                        backgroundColor: scheme.primaryContainer,
                        size: 48,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'No spending recorded in ${report.selectedMonthLabel}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Log a few expenses or income entries — or pick another month above — to unlock live category drains, money-leak detection, and smart budget caps.',
                        textAlign: TextAlign.center,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: cfo.subtleText),
                      ),
                      if (canPost) ...[
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () async {
                            await openAddTransactionSheet(
                              context,
                              profile,
                              initialType: TransactionType.expense,
                            );
                            if (mounted) {
                              await _reload(
                                profile,
                                yearMonth: report.selectedYearMonth,
                              );
                            }
                          },
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Log Expense'),
                        ),
                      ],
                    ],
                  ),
                ),
              ] else ...[
                // 2. 50 / 30 / 20 Health Breakdown
                const SizedBox(height: AppSpacing.md),
                StaggeredFadeSlide(
                  index: 1,
                  child: _Rule503020Card(
                    snapshot: report.rule503020,
                    currencyCode: ccy,
                    masked: masked,
                  ),
                ),

                // 3. Top Categories — Where Most Money Goes
                if (report.categories.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  SectionHeader(
                    title: 'Where Your Money Goes',
                    subtitle: 'Ranked categories with 3-month spike detection',
                    trailingLabel: 'Budget Plan',
                    onTrailingPressed: () => setState(() => _activeTab = 1),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  StaggeredFadeSlide(
                    index: 2,
                    child: PressScaleCard(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (
                            var i = 0;
                            i < report.categories.length && i < 6;
                            i++
                          ) ...[
                            if (i > 0) Divider(height: 18, color: cfo.divider),
                            _CategoryAuditRow(
                              item: report.categories[i],
                              currencyCode: ccy,
                              masked: masked,
                              canCap:
                                  canManageBudgets &&
                                  report.categories[i].categoryId != null,
                              onQuickCap: () {
                                final cat = report.categories[i];
                                final target =
                                    CfoAdvisorEngine.roundFriendlyBudget(
                                      (cat.spendMinor *
                                              (cat.bucket == SpendBucket.wants
                                                  ? 0.85
                                                  : 1.0))
                                          .round(),
                                      ccy,
                                    );
                                _applyBudgetAction(
                                  context,
                                  profile,
                                  CoachBudgetAction(
                                    name: '${cat.categoryName} Cap',
                                    limitMinor: target,
                                    categoryId: cat.categoryId,
                                    categoryName: cat.categoryName,
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],

                // 4. Top Items / Merchants You Spend Most On
                if (report.topMerchants.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  const SectionHeader(
                    title: 'Top Things You Spend Most On',
                    subtitle: 'Highest total outflows grouped by merchant/item',
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  StaggeredFadeSlide(
                    index: 3,
                    child: PressScaleCard(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (
                            var i = 0;
                            i < report.topMerchants.length && i < 6;
                            i++
                          ) ...[
                            if (i > 0) Divider(height: 16, color: cfo.divider),
                            _MerchantAuditRow(
                              rank: i + 1,
                              item: report.topMerchants[i],
                              currencyCode: ccy,
                              masked: masked,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],

                // 5. Hidden Money Leaks & Weekend Burn Pattern
                const SizedBox(height: AppSpacing.md),
                StaggeredFadeSlide(
                  index: 4,
                  child: _LeaksAndWeekendCard(
                    leaks: report.moneyLeaks,
                    weekendBurn: report.weekendBurn,
                    currencyCode: ccy,
                    masked: masked,
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
  // TAB 1: SMART BUDGET PLAN & HOW TO MAINTAIN
  // ---------------------------------------------------------------------------
  Widget _buildBudgetPlanTab(
    BuildContext context,
    FinancialProfile profile,
    CfoAdvisorReport report,
    bool masked,
    bool canManageBudgets,
  ) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final plan = report.budgetPlan;
    final ccy = report.currencyCode;

    return RefreshIndicator(
      onRefresh: () => _reload(profile, yearMonth: report.selectedYearMonth),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EnterprisePageContainer.responsivePadding(context, bottom: 40),
        child: EnterprisePageContainer(
          maxWidth: AppBreakpoints.maxContentWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Smart Overall Monthly Budget Suggestion Hero
              StaggeredFadeSlide(
                index: 0,
                child: FintechAccentCard(
                  accent: ModernDialogAccent.brand,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          IconSquircle(
                            icon: Icons.auto_awesome_rounded,
                            iconColor: scheme.primary,
                            backgroundColor: scheme.primaryContainer,
                            size: 38,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Smart Monthly Budget Plan',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                Text(
                                  plan.methodologyLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: scheme.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        plan.methodologyNote,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cfo.subtleText,
                          height: 1.35,
                        ),
                      ),
                      if (plan.recommendedOverallLimitMinor > 0) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _CompactKpiTile(
                                label: 'Monthly Cap',
                                value: Money(
                                  amountMinor:
                                      plan.recommendedOverallLimitMinor,
                                  currencyCode: ccy,
                                ).format(mask: masked),
                                color: scheme.primary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _CompactKpiTile(
                                label: 'Weekly Env',
                                value: Money(
                                  amountMinor: plan.weeklyEnvelopeMinor,
                                  currencyCode: ccy,
                                ).format(mask: masked),
                                color: cfo.transfer,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _CompactKpiTile(
                                label: 'Est. Savings',
                                value: Money(
                                  amountMinor:
                                      plan.estimatedMonthlySavingsMinor,
                                  currencyCode: ccy,
                                ).format(mask: masked),
                                color: cfo.income,
                              ),
                            ),
                          ],
                        ),
                        if (canManageBudgets) ...[
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            key: const Key('coach_apply_overall_budget_btn'),
                            onPressed: _applyingBudget
                                ? null
                                : () => _applyBudgetAction(
                                    context,
                                    profile,
                                    CoachBudgetAction(
                                      name: 'Smart Monthly Budget',
                                      limitMinor:
                                          plan.recommendedOverallLimitMinor,
                                    ),
                                  ),
                            icon: const Icon(Icons.bolt_rounded, size: 18),
                            label: Text(
                              plan.hasOverallBudgetAlready
                                  ? 'Apply New Monthly Guard'
                                  : '1-Tap Apply Monthly Budget',
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),

              // 2. Per-Category Recommended Caps
              if (plan.categorySuggestions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                const SectionHeader(
                  title: 'Recommended Category Caps',
                  subtitle: '1-tap spending limits tailored to your history',
                ),
                const SizedBox(height: AppSpacing.xs),
                for (var i = 0; i < plan.categorySuggestions.length; i++) ...[
                  StaggeredFadeSlide(
                    index: i + 1,
                    child: _SuggestedCategoryCard(
                      suggestion: plan.categorySuggestions[i],
                      currencyCode: ccy,
                      masked: masked,
                      canApply:
                          canManageBudgets &&
                          plan.categorySuggestions[i].categoryId != null &&
                          !_applyingBudget,
                      onApply: () {
                        final s = plan.categorySuggestions[i];
                        _applyBudgetAction(
                          context,
                          profile,
                          CoachBudgetAction(
                            name: '${s.categoryName} Cap',
                            limitMinor: s.suggestedLimitMinor,
                            categoryId: s.categoryId,
                            categoryName: s.categoryName,
                          ),
                        );
                      },
                    ),
                  ),
                  if (i < plan.categorySuggestions.length - 1)
                    const SizedBox(height: AppSpacing.xs),
                ],
              ],

              // 3. How to Maintain Your Budget Playbook
              const SizedBox(height: AppSpacing.md),
              const SectionHeader(
                title: 'How to Maintain Your Budget',
                subtitle: 'Actionable rules personalized to your spending pace',
              ),
              const SizedBox(height: AppSpacing.xs),
              StaggeredFadeSlide(
                index: 5,
                child: PressScaleCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (
                        var i = 0;
                        i < report.maintenanceTips.length;
                        i++
                      ) ...[
                        if (i > 0) Divider(height: 18, color: cfo.divider),
                        _MaintenanceTipRow(
                          index: i + 1,
                          tip: report.maintenanceTips[i],
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: cfo.surfaceTonal,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(color: cfo.divider),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      size: 16,
                      color: cfo.income,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Powered by 100% free on-device financial algorithms (50/30/20, Weighted Moving Average, Pareto & Spike Detection). Your ledger never leaves this device.',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cfo.subtleText,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 2: ASK CFO COACH (INTERACTIVE OFFLINE AI Q&A)
  // ---------------------------------------------------------------------------
  Widget _buildAskCoachTab(
    BuildContext context,
    FinancialProfile profile,
    CfoAdvisorReport report,
    bool masked,
    bool canManageBudgets,
  ) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;

    const quickPrompts = [
      'Where is my money going?',
      'Suggest a budget',
      'How to maintain my budget?',
      'Find hidden leaks',
      'How can I save 5000?',
      'Compare vs last month',
      'Will I overspend?',
    ];

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: _chatScrollCtrl,
            padding: EnterprisePageContainer.responsivePadding(
              context,
              top: 12,
              bottom: 16,
            ),
            child: EnterprisePageContainer(
              maxWidth: AppBreakpoints.maxContentWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final msg in _messages)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: msg.isUser
                          ? Align(
                              alignment: Alignment.centerRight,
                              child: Container(
                                constraints: const BoxConstraints(
                                  maxWidth: 320,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.primary,
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(16),
                                    topRight: Radius.circular(16),
                                    bottomLeft: Radius.circular(16),
                                    bottomRight: Radius.circular(4),
                                  ),
                                ),
                                child: Text(
                                  msg.text ?? '',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: scheme.onPrimary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                            )
                          : _CoachReplyBubble(
                              reply: msg.reply!,
                              canManageBudgets:
                                  canManageBudgets && !_applyingBudget,
                              onApplyAction: (action) =>
                                  _applyBudgetAction(context, profile, action),
                            ),
                    ),
                ],
              ),
            ),
          ),
        ),
        // Quick question suggestion chips
        Container(
          decoration: BoxDecoration(
            color: cfo.surfaceElevated,
            border: Border(top: BorderSide(color: cfo.divider)),
          ),
          padding: EdgeInsets.fromLTRB(
            12,
            8,
            12,
            MediaQuery.viewPaddingOf(context).bottom + 10,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppBreakpoints.maxContentWidth,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 32,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: quickPrompts.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (context, idx) {
                        final prompt = quickPrompts[idx];
                        return Material(
                          color: cfo.surfaceTonal,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusFull,
                            ),
                            side: BorderSide(color: cfo.divider),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusFull,
                            ),
                            onTap: () => _sendQuestion(prompt),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                              ),
                              child: Center(
                                child: Text(
                                  prompt,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: scheme.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FintechTextField(
                          key: const Key('coach_chat_input'),
                          label: 'Ask about budgets, spending, or savings...',
                          controller: _chatCtrl,
                          compact: true,
                          leadingIcon: Icons.auto_awesome_outlined,
                          textInputAction: TextInputAction.send,
                          onSubmitted: _sendQuestion,
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        key: const Key('coach_chat_send_btn'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(48, 46),
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusMd,
                            ),
                          ),
                        ),
                        onPressed: () => _sendQuestion(_chatCtrl.text),
                        child: const Icon(Icons.send_rounded, size: 20),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CompactKpiTile extends StatelessWidget {
  const _CompactKpiTile({
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
        border: Border.all(color: cfo.divider.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cfo.subtleText,
              fontSize: 10.5,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
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

class _Rule503020Card extends StatelessWidget {
  const _Rule503020Card({
    required this.snapshot,
    required this.currencyCode,
    required this.masked,
  });

  final Rule503020Snapshot snapshot;
  final String currencyCode;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;

    return PressScaleCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconSquircle(
                icon: Icons.balance_rounded,
                iconColor: scheme.primary,
                backgroundColor: scheme.primaryContainer,
                size: 34,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '50 / 30 / 20 Money Balance',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      snapshot.hasIncomeBasis
                          ? 'Actual share of monthly income vs ideal targets'
                          : 'Share of monthly spend • Log income for savings %',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _BucketBarRow(
            label: 'Needs (Target 50%)',
            amountMinor: snapshot.needsMinor,
            percent: snapshot.needsPct,
            targetPercent: 50,
            currencyCode: currencyCode,
            color: scheme.primary,
            masked: masked,
          ),
          const SizedBox(height: 8),
          _BucketBarRow(
            label: 'Wants (Target 30%)',
            amountMinor: snapshot.wantsMinor,
            percent: snapshot.wantsPct,
            targetPercent: 30,
            currencyCode: currencyCode,
            color: snapshot.wantsPct > 35 ? cfo.expense : cfo.warning,
            masked: masked,
          ),
          const SizedBox(height: 8),
          _BucketBarRow(
            label: 'Savings & Debt (Target 20%)',
            amountMinor: snapshot.savingsMinor,
            percent: snapshot.savingsPct,
            targetPercent: 20,
            currencyCode: currencyCode,
            color: cfo.income,
            masked: masked,
          ),
        ],
      ),
    );
  }
}

class _BucketBarRow extends StatelessWidget {
  const _BucketBarRow({
    required this.label,
    required this.amountMinor,
    required this.percent,
    required this.targetPercent,
    required this.currencyCode,
    required this.color,
    required this.masked,
  });

  final String label;
  final int amountMinor;
  final double percent;
  final int targetPercent;
  final String currencyCode;
  final Color color;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 112),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: MoneyText(
                  money: Money(
                    amountMinor: amountMinor,
                    currencyCode: currencyCode,
                  ),
                  masked: masked,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              masked ? '••%' : '${percent.round()}%',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        AnimatedProgressBar(
          value: masked ? 0.0 : (percent / 100.0).clamp(0.0, 1.0),
          color: color,
          height: 6,
        ),
      ],
    );
  }
}

class _CategoryAuditRow extends StatelessWidget {
  const _CategoryAuditRow({
    required this.item,
    required this.currencyCode,
    required this.masked,
    required this.canCap,
    required this.onQuickCap,
  });

  final CategoryAuditItem item;
  final String currencyCode;
  final bool masked;
  final bool canCap;
  final VoidCallback onQuickCap;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final barColor = item.isSpike
        ? cfo.expense
        : (item.bucket == SpendBucket.wants ? cfo.warning : scheme.primary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
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
                        item.categoryName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      FintechStatusPill(
                        label: item.bucket.label,
                        foreground: item.bucket == SpendBucket.wants
                            ? cfo.warning
                            : scheme.primary,
                        background: item.bucket == SpendBucket.wants
                            ? cfo.warningContainer
                            : scheme.primaryContainer,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item.txCount} tx${item.deltaVsAvgPercent != null && !masked ? ' • ${item.deltaVsAvgPercent! >= 0 ? '+' : ''}${item.deltaVsAvgPercent!.round()}% vs 3-mo avg' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: item.isSpike ? cfo.expense : cfo.subtleText,
                      fontWeight: item.isSpike
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 112),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: MoneyText(
                      money: Money(
                        amountMinor: item.spendMinor,
                        currencyCode: currencyCode,
                      ),
                      masked: masked,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                if (canCap)
                  InkWell(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                    onTap: onQuickCap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Text(
                        'Set Cap',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: AnimatedProgressBar(
                value: masked
                    ? 0.0
                    : (item.sharePercent / 100.0).clamp(0.0, 1.0),
                color: barColor,
                height: 5.5,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              masked ? '••%' : '${item.sharePercent.round()}%',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: barColor,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MerchantAuditRow extends StatelessWidget {
  const _MerchantAuditRow({
    required this.rank,
    required this.item,
    required this.currencyCode,
    required this.masked,
  });

  final int rank;
  final TopMerchantItem item;
  final String currencyCode;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: rank == 1 ? cfo.expenseContainer : cfo.surfaceTonal,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Text(
            '#$rank',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: rank == 1 ? cfo.expense : scheme.onSurface,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                '${item.primaryCategory} • ${item.txCount}x • Avg ${Money(amountMinor: item.averageMinor, currencyCode: currencyCode).format(mask: masked)}',
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
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 108),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: MoneyText(
                  money: Money(
                    amountMinor: item.totalMinor,
                    currencyCode: currencyCode,
                  ),
                  masked: masked,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            Text(
              masked ? '••%' : '${item.sharePercent.round()}% of spend',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cfo.subtleText,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LeaksAndWeekendCard extends StatelessWidget {
  const _LeaksAndWeekendCard({
    required this.leaks,
    required this.weekendBurn,
    required this.currencyCode,
    required this.masked,
  });

  final List<MoneyLeakItem> leaks;
  final WeekendBurnInsight weekendBurn;
  final String currencyCode;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    return PressScaleCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconSquircle(
                icon: Icons.water_drop_outlined,
                iconColor: cfo.warning,
                backgroundColor: cfo.warningContainer,
                size: 34,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Money Leaks & Weekend Burn',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Small repeat habits & Fri–Sun velocity check',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _CompactKpiTile(
                  label: 'Mon–Thu Avg/Day',
                  value: Money(
                    amountMinor: weekendBurn.weekdayDailyAvgMinor,
                    currencyCode: currencyCode,
                  ).format(mask: masked),
                  color: cfo.income,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CompactKpiTile(
                  label: 'Fri–Sun Avg/Day',
                  value: Money(
                    amountMinor: weekendBurn.weekendDailyAvgMinor,
                    currencyCode: currencyCode,
                  ).format(mask: masked),
                  color: weekendBurn.isWeekendHeavy
                      ? cfo.expense
                      : cfo.transfer,
                ),
              ),
            ],
          ),
          if (leaks.isNotEmpty) ...[
            const SizedBox(height: 10),
            Divider(height: 1, color: cfo.divider),
            const SizedBox(height: 8),
            for (var i = 0; i < leaks.length && i < 3; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${leaks[i].label} (${leaks[i].txCount}x/mo)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${Money(amountMinor: leaks[i].annualizedMinor, currencyCode: currencyCode).format(mask: masked)}/yr pace • Cut 30% to save ${Money(amountMinor: leaks[i].potentialAnnualSavingMinor, currencyCode: currencyCode).format(mask: masked)}/yr',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: cfo.subtleText),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FintechStatusPill(
                    label: Money(
                      amountMinor: leaks[i].totalMinor,
                      currencyCode: currencyCode,
                    ).format(mask: masked),
                    foreground: cfo.warning,
                    background: cfo.warningContainer,
                  ),
                ],
              ),
            ],
          ] else ...[
            const SizedBox(height: 8),
            Text(
              'No frequent micro-spend leaks (>= 3 discretionary visits/mo) flagged for this month.',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
            ),
          ],
        ],
      ),
    );
  }
}

class _SuggestedCategoryCard extends StatelessWidget {
  const _SuggestedCategoryCard({
    required this.suggestion,
    required this.currencyCode,
    required this.masked,
    required this.canApply,
    required this.onApply,
  });

  final SuggestedCategoryBudget suggestion;
  final String currencyCode;
  final bool masked;
  final bool canApply;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    return PressScaleCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
                          suggestion.categoryName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        FintechStatusPill(
                          label: suggestion.bucket.label,
                          foreground: suggestion.bucket == SpendBucket.wants
                              ? cfo.warning
                              : scheme.primary,
                          background: suggestion.bucket == SpendBucket.wants
                              ? cfo.warningContainer
                              : scheme.primaryContainer,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      suggestion.rationale,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (suggestion.alreadyBudgeted)
                FintechStatusPill(
                  label: 'Capped',
                  showDot: true,
                  foreground: cfo.income,
                  background: cfo.incomeContainer,
                )
              else if (canApply)
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: onApply,
                  child: const Text('Set Cap'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Current: ${Money(amountMinor: suggestion.currentSpendMinor, currencyCode: currencyCode).format(mask: masked)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cfo.subtleText,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                'Suggested: ${Money(amountMinor: suggestion.suggestedLimitMinor, currencyCode: currencyCode).format(mask: masked)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MaintenanceTipRow extends StatelessWidget {
  const _MaintenanceTipRow({required this.index, required this.tip});
  final int index;
  final MaintenanceTip tip;

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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (tip.impactLabel != null)
                    FintechStatusPill(
                      label: tip.impactLabel!,
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

class _CoachReplyBubble extends StatelessWidget {
  const _CoachReplyBubble({
    required this.reply,
    required this.canManageBudgets,
    required this.onApplyAction,
  });

  final CoachReply reply;
  final bool canManageBudgets;
  final ValueChanged<CoachBudgetAction> onApplyAction;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.centerLeft,
      child: PressScaleCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconSquircle(
                  icon: Icons.auto_awesome_rounded,
                  iconColor: scheme.primary,
                  backgroundColor: scheme.primaryContainer,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    reply.headline,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              reply.summary,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(height: 1.4),
            ),
            if (reply.metrics.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final m in reply.metrics)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: cfo.surfaceTonal,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusSm,
                        ),
                        border: Border.all(color: cfo.divider),
                      ),
                      child: Text(
                        '${m.label}: ${m.value}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                ],
              ),
            ],
            if (reply.actionSteps.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final step in reply.actionSteps)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '• ',
                        style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          step,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: cfo.subtleText, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (reply.budgetAction != null && canManageBudgets) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed: () => onApplyAction(reply.budgetAction!),
                  icon: const Icon(Icons.bolt_rounded, size: 16),
                  label: Text('Apply ${reply.budgetAction!.name}'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
