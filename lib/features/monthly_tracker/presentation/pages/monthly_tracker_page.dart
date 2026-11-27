import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/financial_engine/currency.dart';
import '../../../../core/financial_engine/money.dart';
import '../../../../core/financial_engine/monthly_tracker_engine.dart';
import '../../../../core/utilities/clock.dart';
import '../../../../shared/widgets/classic_motion.dart';
import '../../../../shared/widgets/credit_salary_dialog.dart';
import '../../../../shared/widgets/enterprise_layout.dart';
import '../../../../shared/widgets/fintech_widgets.dart';
import '../../../../shared/widgets/modern_dialogs.dart';
import '../../../../shared/widgets/modern_dropdown.dart';
import '../../../../shared/widgets/modern_inputs.dart';
import '../../../dashboard/presentation/bloc/dashboard_bloc.dart';
import '../../../notifications/presentation/bloc/notifications_cubit.dart';
import '../../../profiles/domain/entities/profile_entity.dart';
import '../../../profiles/presentation/bloc/active_profile_cubit.dart';
import '../../../settings/presentation/bloc/settings_cubit.dart';
import '../../../transactions/presentation/bloc/transactions_bloc.dart';
import '../../data/monthly_tracker_service.dart';
import '../../domain/entities/bucket_list_item_entity.dart';
import '../widgets/bucket_item_editor_dialog.dart';
import '../widgets/bucket_list_tab.dart';
import '../widgets/extra_income_tab.dart';
import '../widgets/month_overview_tab.dart';
import '../widgets/month_recap_dialog.dart';
import '../widgets/windfall_split_dialog.dart';

/// `SCR-MONTH-001` — Dedicated Monthly Tracker, Smart Bucket List & Extra-Income
/// Split Studio (`/monthly`).
class MonthlyTrackerPage extends StatefulWidget {
  const MonthlyTrackerPage({super.key, this.initialTab = 0});

  /// `0` = This Month, `1` = Bucket List, `2` = Extra Income.
  final int initialTab;

  @override
  State<MonthlyTrackerPage> createState() => _MonthlyTrackerPageState();
}

class _MonthlyTrackerPageState extends State<MonthlyTrackerPage> {
  late int _activeTab;
  late int _year;
  late int _month;

  MonthlyTrackerViewData? _data;
  bool _loading = true;
  String? _loadedProfileId;
  int _requestEpoch = 0;

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab.clamp(0, 2);
    final now = GetIt.I<UtcClock>().nowUtc();
    _year = now.year;
    _month = now.month;
  }

  Future<void> _reload(FinancialProfile profile) async {
    final epoch = ++_requestEpoch;
    _loadedProfileId = profile.id.value;
    setState(() => _loading = true);
    final res = await GetIt.I<MonthlyTrackerService>().loadMonth(
      profile: profile,
      year: _year,
      month: _month,
    );
    if (!mounted || epoch != _requestEpoch) return;
    setState(() {
      _data = res.valueOrNull;
      _loading = false;
    });
  }

  void _shiftMonth(FinancialProfile profile, int delta) {
    final currentKey = MonthlyTrackerEngine.monthKey(_year, _month);
    final nextKey = MonthlyTrackerEngine.shiftMonth(currentKey, delta);
    final now = GetIt.I<UtcClock>().nowUtc();
    final maxFutureKey = MonthlyTrackerEngine.shiftMonth(
      MonthlyTrackerEngine.monthKey(now.year, now.month),
      3,
    );
    if (nextKey.compareTo(maxFutureKey) > 0) return;

    final (ny, nm) = MonthlyTrackerEngine.parseMonthKey(nextKey);
    HapticFeedback.selectionClick();
    setState(() {
      _year = ny;
      _month = nm;
    });
    _reload(profile);
  }

  bool _canGoNextMonth() {
    final now = GetIt.I<UtcClock>().nowUtc();
    final currentKey = MonthlyTrackerEngine.monthKey(_year, _month);
    final maxFutureKey = MonthlyTrackerEngine.shiftMonth(
      MonthlyTrackerEngine.monthKey(now.year, now.month),
      3,
    );
    return currentKey.compareTo(maxFutureKey) < 0;
  }

  Future<void> _openBucketEditor(
    BuildContext context,
    FinancialProfile profile,
    MonthlyTrackerViewData data, {
    BucketListItemEntity? existing,
  }) async {
    final dashBloc = context.read<DashboardBloc?>();
    final draft = await showModernDialog<BucketItemDraft>(
      context: context,
      builder: (_) => BucketItemEditorDialog(
        currencyCode: profile.baseCurrencyCode,
        baseYear: _year,
        baseMonth: _month,
        expenseCategories: data.expenseCategories,
        existing: existing,
        snapshot: data.snapshot,
      ),
    );
    if (draft == null || !context.mounted) return;

    final res = await GetIt.I<MonthlyTrackerService>().saveItem(
      profile: profile,
      existing: existing,
      name: draft.name,
      estimatedAmountMinor: draft.estimatedAmountMinor,
      priority: draft.priority,
      targetYearMonth: draft.targetYearMonth,
      dueDateUtc: draft.dueDateUtc,
      reminderAtUtc: draft.reminderAtUtc,
      categoryId: draft.categoryId,
      note: draft.note,
    );
    if (!context.mounted) return;
    if (res.isSuccess) {
      dashBloc?.add(const DashboardRefreshRequested());
      showFintechToast(
        context,
        existing == null
            ? 'Added "${draft.name}" to Bucket List.'
            : 'Updated "${draft.name}".',
        tone: FintechToastTone.success,
      );
      await _reload(profile);
    } else {
      showFintechToast(
        context,
        res.failureOrNull?.message ?? 'Could not save bucket item.',
        tone: FintechToastTone.danger,
      );
    }
  }

  Future<void> _deleteItem(
    BuildContext context,
    FinancialProfile profile,
    BucketListItemEntity item,
  ) async {
    final dashBloc = context.read<DashboardBloc?>();
    final confirmed = await showModernConfirmDialog(
      context: context,
      title: 'Delete Bucket Item?',
      subtitle: item.name,
      icon: Icons.delete_outline_rounded,
      accent: ModernDialogAccent.danger,
      confirmLabel: 'Delete',
      message: 'Remove "${item.name}" from your Bucket List?',
    );
    if (confirmed != true || !context.mounted) return;

    final res = await GetIt.I<MonthlyTrackerService>().deleteItem(
      profile,
      item.id,
    );
    if (!context.mounted) return;
    if (res.isSuccess) {
      dashBloc?.add(const DashboardRefreshRequested());
      showFintechToast(
        context,
        'Removed "${item.name}".',
        tone: FintechToastTone.info,
      );
      await _reload(profile);
    }
  }

  Future<void> _openRecapDialog(
    BuildContext context,
    MonthlyTrackerViewData data,
    bool masked,
  ) {
    return showModernDialog<void>(
      context: context,
      builder: (_) => MonthRecapDialog(
        snapshot: data.snapshot,
        boughtBucketCount: data.purchasedThisMonthItems.length,
        masked: masked,
      ),
    );
  }

  Future<void> _jumpToCurrentMonth(FinancialProfile profile) async {
    final now = GetIt.I<UtcClock>().nowUtc();
    if (_year == now.year && _month == now.month) return;
    HapticFeedback.selectionClick();
    setState(() {
      _year = now.year;
      _month = now.month;
    });
    await _reload(profile);
  }

  Future<void> _markBought(
    BuildContext context,
    FinancialProfile profile,
    MonthlyTrackerViewData data,
    BucketListItemEntity item,
  ) async {
    if (data.liquidAccounts.isEmpty || data.expenseCategories.isEmpty) {
      showFintechToast(
        context,
        'Create an account and expense category first to log purchases.',
        tone: FintechToastTone.info,
      );
      return;
    }

    final spec = CurrencyCatalog.requireByCode(profile.baseCurrencyCode);
    final factor = math.pow(10, spec.minorUnit).toInt();
    final initialText = spec.minorUnit == 0
        ? '${item.estimatedAmountMinor}'
        : (item.estimatedAmountMinor % factor == 0
              ? '${item.estimatedAmountMinor ~/ factor}'
              : (item.estimatedAmountMinor / factor).toStringAsFixed(
                  spec.minorUnit,
                ));

    final result =
        await showModernDialog<
          ({int actualMinor, String accountId, String categoryId})
        >(
          context: context,
          builder: (_) => _MarkBoughtDialog(
            currencyCode: profile.baseCurrencyCode,
            item: item,
            initialAmountText: initialText,
            accounts: data.liquidAccounts,
            categories: data.expenseCategories,
          ),
        );
    if (result == null || !context.mounted) return;

    final dashBloc = _maybeRead<DashboardBloc>(context);
    final txBloc = _maybeRead<TransactionsBloc>(context);
    final notifCubit = _maybeRead<NotificationsCubit>(context);
    final res = await GetIt.I<MonthlyTrackerService>().markPurchased(
      profile: profile,
      item: item,
      actualAmountMinor: result.actualMinor,
      accountId: result.accountId,
      categoryId: result.categoryId,
      dateUtc: GetIt.I<UtcClock>().nowUtc(),
    );
    if (!context.mounted) return;
    if (res.isSuccess) {
      HapticFeedback.mediumImpact();
      dashBloc?.add(const DashboardRefreshRequested());
      txBloc?.add(const TransactionsLoadRequested());
      notifCubit?.triggerCelebration();
      showFintechToast(
        context,
        'Logged purchase for "${item.name}".',
        tone: FintechToastTone.success,
      );
      await _reload(profile);
    } else {
      showFintechToast(
        context,
        res.failureOrNull?.message ?? 'Could not record purchase.',
        tone: FintechToastTone.danger,
      );
    }
  }

  T? _maybeRead<T>(BuildContext context) {
    try {
      return context.read<T>();
    } catch (_) {
      return null;
    }
  }

  Future<void> _addMoneyToItem(
    BuildContext context,
    FinancialProfile profile,
    BucketListItemEntity item,
  ) async {
    final dashBloc = _maybeRead<DashboardBloc>(context);
    final amountMinor = await showModernDialog<int>(
      context: context,
      builder: (_) =>
          _AddFundsDialog(currencyCode: profile.baseCurrencyCode, item: item),
    );
    if (amountMinor == null || !context.mounted) return;

    final res = await GetIt.I<MonthlyTrackerService>().addFunds(
      profile,
      item,
      amountMinor,
    );
    if (!context.mounted) return;
    if (res.isSuccess) {
      dashBloc?.add(const DashboardRefreshRequested());
      showFintechToast(
        context,
        'Added funds to "${item.name}".',
        tone: FintechToastTone.success,
      );
      await _reload(profile);
    } else {
      showFintechToast(
        context,
        res.failureOrNull?.message ?? 'Could not add funds.',
        tone: FintechToastTone.danger,
      );
    }
  }

  Future<void> _reserveInBudget(
    BuildContext context,
    FinancialProfile profile,
    BucketListItemEntity item,
  ) async {
    final dashBloc = _maybeRead<DashboardBloc>(context);
    final res = await GetIt.I<MonthlyTrackerService>().reserveInBudget(
      profile: profile,
      item: item,
    );
    if (!context.mounted) return;
    if (res.isSuccess) {
      dashBloc?.add(const DashboardRefreshRequested());
      showFintechToast(
        context,
        'Reserved budget envelope for "${item.name}".',
        tone: FintechToastTone.success,
      );
      await _reload(profile);
    } else {
      showFintechToast(
        context,
        res.failureOrNull?.message ?? 'Could not reserve in budget.',
        tone: FintechToastTone.warning,
      );
    }
  }

  Future<void> _convertToGoal(
    BuildContext context,
    FinancialProfile profile,
    BucketListItemEntity item,
    BucketItemPlan? plan,
  ) async {
    final dashBloc = _maybeRead<DashboardBloc>(context);
    final res = await GetIt.I<MonthlyTrackerService>().convertToGoal(
      profile: profile,
      item: item,
      plan: plan,
    );
    if (!context.mounted) return;
    if (res.isSuccess) {
      dashBloc?.add(const DashboardRefreshRequested());
      showFintechToast(
        context,
        'Linked "${item.name}" to Savings Goals.',
        tone: FintechToastTone.success,
      );
      await _reload(profile);
    } else {
      showFintechToast(
        context,
        res.failureOrNull?.message ?? 'Could not convert to goal.',
        tone: FintechToastTone.danger,
      );
    }
  }

  Future<void> _postponeItem(
    BuildContext context,
    FinancialProfile profile,
    BucketListItemEntity item,
  ) async {
    final dashBloc = _maybeRead<DashboardBloc>(context);
    final res = await GetIt.I<MonthlyTrackerService>().postponeItem(
      profile,
      item,
    );
    if (!context.mounted) return;
    if (res.isSuccess) {
      dashBloc?.add(const DashboardRefreshRequested());
      showFintechToast(
        context,
        'Moved "${item.name}" to ${res.valueOrNull?.targetYearMonth}.',
        tone: FintechToastTone.info,
      );
      await _reload(profile);
    }
  }

  Future<void> _openWindfallDialog(
    BuildContext context,
    FinancialProfile profile,
    MonthlyTrackerViewData data, {
    int? initialAmountMinor,
    String? initialSourceLabel,
    String? initialPreset,
  }) async {
    if (data.liquidAccounts.isEmpty) {
      showFintechToast(
        context,
        'Create a bank or cash account first to receive extra income.',
        tone: FintechToastTone.info,
      );
      return;
    }

    final draft = await showModernDialog<WindfallDraft>(
      context: context,
      builder: (_) => WindfallSplitDialog(
        currencyCode: profile.baseCurrencyCode,
        snapshot: data.snapshot,
        accounts: data.liquidAccounts,
        goals: data.activeGoals,
        initialAmountMinor: initialAmountMinor,
        initialSourceLabel: initialSourceLabel,
        initialPreset: initialPreset,
      ),
    );
    if (draft == null || !context.mounted) return;

    final dashBloc = _maybeRead<DashboardBloc>(context);
    final txBloc = _maybeRead<TransactionsBloc>(context);
    final notifCubit = _maybeRead<NotificationsCubit>(context);
    final now = GetIt.I<UtcClock>().nowUtc();
    final txDate = DateTime.utc(
      _year,
      _month,
      math.min<int>(now.day, MonthlyTrackerEngine.daysInMonth(_year, _month)),
      now.hour,
      now.minute,
    );

    final res = await GetIt.I<MonthlyTrackerService>().recordExtraIncome(
      profile: profile,
      amountMinor: draft.amountMinor,
      sourceLabel: draft.sourceLabel,
      accountId: draft.accountId,
      dateUtc: txDate,
      split: draft.split,
      goalId: draft.goalId,
    );
    if (!context.mounted) return;
    if (res.isSuccess) {
      HapticFeedback.mediumImpact();
      dashBloc?.add(const DashboardRefreshRequested());
      txBloc?.add(const TransactionsLoadRequested());
      notifCubit?.triggerCelebration();
      showFintechToast(
        context,
        'Extra income (${draft.sourceLabel}) recorded & split.',
        tone: FintechToastTone.success,
      );
      await _reload(profile);
    } else {
      showFintechToast(
        context,
        res.failureOrNull?.message ?? 'Could not record extra income.',
        tone: FintechToastTone.danger,
      );
    }
  }

  Future<void> _openCreditSalaryDialog(
    BuildContext context,
    FinancialProfile profile,
    MonthlyTrackerViewData data,
  ) async {
    if (data.liquidAccounts.isEmpty) {
      showFintechToast(
        context,
        'Add a bank or cash account first to credit salary.',
        tone: FintechToastTone.info,
      );
      return;
    }

    final monthLabel = DateFormat(
      'MMM yyyy',
    ).format(DateTime.utc(_year, _month, 1));
    final draft = await showModernDialog<CreditSalaryDraft>(
      context: context,
      builder: (_) => CreditSalaryDialog(
        currencyCode: profile.baseCurrencyCode,
        monthLabel: monthLabel,
        defaultAmountMinor: data.snapshot.expectedIncomeMinor,
        accounts: data.liquidAccounts,
        preferredAccountId: data.preferredSalaryAccountId,
        alreadyCredited: data.salaryCreditedThisMonth,
      ),
    );
    if (draft == null || !context.mounted) return;

    final dashBloc = _maybeRead<DashboardBloc>(context);
    final txBloc = _maybeRead<TransactionsBloc>(context);
    final notifCubit = _maybeRead<NotificationsCubit>(context);
    final res = await GetIt.I<MonthlyTrackerService>().creditMonthlySalary(
      profile: profile,
      accountId: draft.accountId,
      amountMinor: draft.amountMinor,
      year: _year,
      month: _month,
      createRecurringRule: draft.createRecurringRule,
      forceDuplicate: data.salaryCreditedThisMonth,
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
        'Credited ${info.accountName} for $monthLabel.',
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
    final cfo = context.cfoColors;

    if (profile == null) {
      return const Scaffold(
        body: EmptyStateView(
          icon: Icons.calendar_month_rounded,
          title: 'No active profile',
          description: 'Select a profile to track your month and bucket list.',
        ),
      );
    }

    if (_loadedProfileId != profile.id.value) {
      _loadedProfileId = profile.id.value;
      Future.microtask(() => _reload(profile));
    }

    final data = _data;
    final monthTitle = DateFormat(
      'MMMM yyyy',
    ).format(DateTime.utc(_year, _month, 1));
    final canManage = profile.permissions.canManageCategoriesAndBudgets;
    final canPost = profile.permissions.canPostTransaction;
    final bucketCount = data?.thisMonthItems.length ?? 0;

    final nowUtc = GetIt.I<UtcClock>().nowUtc();
    final isCurrentSelectedMonth =
        _year == nowUtc.year && _month == nowUtc.month;
    final motionFast = AppMotion.resolve(context, AppMotion.fast);

    return Scaffold(
      appBar: EnterpriseAppBar(
        title: const Text('Monthly Tracker'),
        actions: [
          IconButton(
            key: const Key('monthly_recap_btn'),
            tooltip: 'Month Scorecard',
            onPressed: data == null
                ? null
                : () => _openRecapDialog(context, data, hideBalances),
            icon: const Icon(Icons.auto_awesome_rounded),
          ),
        ],
      ),
      body: Column(
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Month Switcher Pill + Today Quick Jump
                  Center(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: cfo.surfaceTonal,
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusFull,
                            ),
                            border: Border.all(color: cfo.divider),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                key: const Key('monthly_month_prev'),
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _shiftMonth(profile, -1),
                                icon: const Icon(Icons.chevron_left_rounded),
                              ),
                              Flexible(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: AnimatedSwitcher(
                                    duration: motionFast,
                                    child: Text(
                                      monthTitle,
                                      key: ValueKey(monthTitle),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                key: const Key('monthly_month_next'),
                                visualDensity: VisualDensity.compact,
                                onPressed: _canGoNextMonth()
                                    ? () => _shiftMonth(profile, 1)
                                    : null,
                                icon: const Icon(Icons.chevron_right_rounded),
                              ),
                            ],
                          ),
                        ),
                        if (!isCurrentSelectedMonth)
                          ActionChip(
                            key: const Key('monthly_month_today'),
                            avatar: const Icon(Icons.today_rounded, size: 15),
                            label: const Text('Today'),
                            onPressed: () => _jumpToCurrentMonth(profile),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  FintechSegmentedControl<int>(
                    key: const Key('monthly_tracker_tabs'),
                    selected: _activeTab,
                    options: [
                      const FintechSegmentOption(
                        value: 0,
                        label: 'This Month',
                        icon: Icons.insights_rounded,
                      ),
                      FintechSegmentOption(
                        value: 1,
                        label: 'Bucket List',
                        icon: Icons.checklist_rounded,
                        badgeCount: bucketCount,
                      ),
                      const FintechSegmentOption(
                        value: 2,
                        label: 'Extra Income',
                        icon: Icons.savings_outlined,
                      ),
                    ],
                    onChanged: (idx) {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      setState(() => _activeTab = idx);
                    },
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ClassicContentSwitcher(
              stateKey: _loading && data == null
                  ? 'loading'
                  : data == null
                  ? 'empty'
                  : 'loaded',
              child: _loading && data == null
                  ? const DashboardSkeletonView()
                  : data == null
                  ? EmptyStateView(
                      icon: Icons.calendar_month_rounded,
                      title: 'Unable to load Monthly Tracker',
                      description: 'Pull down or tap retry to load this month.',
                      actionLabel: 'Retry',
                      onAction: () => _reload(profile),
                    )
                  : ClassicTabSwitcher(
                      activeIndex: _activeTab,
                      child: switch (_activeTab) {
                        1 => BucketListTab(
                          data: data,
                          masked: hideBalances,
                          canManage: canManage,
                          onRefresh: () => _reload(profile),
                          onAddItem: () =>
                              _openBucketEditor(context, profile, data),
                          onEditItem: (item) => _openBucketEditor(
                            context,
                            profile,
                            data,
                            existing: item,
                          ),
                          onDeleteItem: (item) =>
                              _deleteItem(context, profile, item),
                          onMarkBought: (item) =>
                              _markBought(context, profile, data, item),
                          onAddMoney: (item) =>
                              _addMoneyToItem(context, profile, item),
                          onReserveInBudget: (item) =>
                              _reserveInBudget(context, profile, item),
                          onConvertToGoal: (item, plan) =>
                              _convertToGoal(context, profile, item, plan),
                          onPostpone: (item) =>
                              _postponeItem(context, profile, item),
                        ),
                        2 => ExtraIncomeTab(
                          data: data,
                          masked: hideBalances,
                          canPost: canPost,
                          onRefresh: () => _reload(profile),
                          onAddExtraIncome: () =>
                              _openWindfallDialog(context, profile, data),
                          onQuickSplitExtraIncome:
                              ({amountMinor, sourceLabel, preset}) =>
                                  _openWindfallDialog(
                                    context,
                                    profile,
                                    data,
                                    initialAmountMinor: amountMinor,
                                    initialSourceLabel: sourceLabel,
                                    initialPreset: preset,
                                  ),
                        ),
                        _ => MonthOverviewTab(
                          data: data,
                          masked: hideBalances,
                          onRefresh: () => _reload(profile),
                          onPlanPurchase: () => setState(() => _activeTab = 1),
                          onAddExtraIncome: () {
                            setState(() => _activeTab = 2);
                            if (canPost) {
                              Future.microtask(() {
                                if (context.mounted) {
                                  _openWindfallDialog(context, profile, data);
                                }
                              });
                            }
                          },
                          onOpenRecap: () =>
                              _openRecapDialog(context, data, hideBalances),
                          onCreditSalary: canPost
                              ? () => _openCreditSalaryDialog(
                                  context,
                                  profile,
                                  data,
                                )
                              : null,
                        ),
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MarkBoughtDialog extends StatefulWidget {
  const _MarkBoughtDialog({
    required this.currencyCode,
    required this.item,
    required this.initialAmountText,
    required this.accounts,
    required this.categories,
  });

  final String currencyCode;
  final BucketListItemEntity item;
  final String initialAmountText;
  final List accounts;
  final List categories;

  @override
  State<_MarkBoughtDialog> createState() => _MarkBoughtDialogState();
}

class _MarkBoughtDialogState extends State<_MarkBoughtDialog> {
  late final TextEditingController _amountCtrl;
  late String _accountId;
  late String _categoryId;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(text: widget.initialAmountText);
    _accountId = widget.accounts.first.id as String;
    final hasMatch = widget.categories.any(
      (c) => c.id == widget.item.categoryId,
    );
    _categoryId = hasMatch
        ? widget.item.categoryId!
        : widget.categories.first.id as String;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  int _parseMinor(String raw) {
    final clean = raw.trim().replaceAll(',', '');
    if (clean.isEmpty) return 0;
    final spec = CurrencyCatalog.requireByCode(widget.currencyCode);
    return Money.parseDecimal(clean, currency: spec).valueOrNull?.amountMinor ??
        0;
  }

  @override
  Widget build(BuildContext context) {
    final valid = _parseMinor(_amountCtrl.text) > 0;
    return ModernDialogShell(
      title: 'Mark "${widget.item.name}" Bought',
      subtitle: 'Posts a real expense into your ledger',
      icon: Icons.shopping_bag_rounded,
      accent: ModernDialogAccent.success,
      confirmLabel: 'Post Expense',
      confirmKey: const Key('bucket_bought_confirm_btn'),
      onConfirm: valid
          ? () => Navigator.of(context).pop((
              actualMinor: _parseMinor(_amountCtrl.text),
              accountId: _accountId,
              categoryId: _categoryId,
            ))
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FintechTextField(
            label: 'Actual Amount Paid (${widget.currencyCode})',
            controller: _amountCtrl,
            compact: true,
            leadingIcon: Icons.payments_outlined,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          FintechDropdownField<String>(
            label: 'Paid From Account',
            value: _accountId,
            options: [
              for (final a in widget.accounts)
                FintechDropdownOption(
                  value: a.id as String,
                  label: a.name as String,
                ),
            ],
            leadingIcon: Icons.account_balance_outlined,
            compact: true,
            onChanged: (v) => setState(() => _accountId = v),
          ),
          const SizedBox(height: 10),
          FintechDropdownField<String>(
            label: 'Expense Category',
            value: _categoryId,
            options: [
              for (final c in widget.categories)
                FintechDropdownOption(
                  value: c.id as String,
                  label: c.name as String,
                ),
            ],
            leadingIcon: Icons.category_outlined,
            compact: true,
            onChanged: (v) => setState(() => _categoryId = v),
          ),
        ],
      ),
    );
  }
}

class _AddFundsDialog extends StatefulWidget {
  const _AddFundsDialog({required this.currencyCode, required this.item});

  final String currencyCode;
  final BucketListItemEntity item;

  @override
  State<_AddFundsDialog> createState() => _AddFundsDialogState();
}

class _AddFundsDialogState extends State<_AddFundsDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  int _parseMinor(String raw) {
    final clean = raw.trim().replaceAll(',', '');
    if (clean.isEmpty) return 0;
    final spec = CurrencyCatalog.requireByCode(widget.currencyCode);
    return Money.parseDecimal(clean, currency: spec).valueOrNull?.amountMinor ??
        0;
  }

  String _minorToPlain(int minor) {
    if (minor <= 0) return '';
    final spec = CurrencyCatalog.requireByCode(widget.currencyCode);
    final factor = math.pow(10, spec.minorUnit).toInt();
    if (spec.minorUnit == 0) return '$minor';
    if (minor % factor == 0) return '${minor ~/ factor}';
    return (minor / factor).toStringAsFixed(spec.minorUnit);
  }

  @override
  Widget build(BuildContext context) {
    final amt = _parseMinor(_ctrl.text);
    final remaining = math.max<int>(0, widget.item.remainingMinor);
    final ccy = widget.currencyCode;
    final spec = CurrencyCatalog.byCode(ccy);
    String fmt(int m) =>
        Money(amountMinor: m, currencyCode: ccy).format(spec: spec);

    return ModernDialogShell(
      title: 'Add Money',
      subtitle:
          '${widget.item.name} · Ring-fences cash in Tracker (bank debits on Buy)',
      icon: Icons.add_card_outlined,
      accent: ModernDialogAccent.brand,
      confirmLabel: 'Save Progress',
      confirmKey: const Key('bucket_add_funds_confirm_btn'),
      onConfirm: amt > 0 ? () => Navigator.of(context).pop(amt) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FintechTextField(
            label: 'Amount to Set Aside ($ccy)',
            controller: _ctrl,
            compact: true,
            leadingIcon: Icons.savings_outlined,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
          if (remaining > 0) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final entry in [
                  (
                    label: '25% (${fmt((remaining * 0.25).round())})',
                    m: (remaining * 0.25).round(),
                  ),
                  (
                    label: '50% (${fmt((remaining * 0.5).round())})',
                    m: (remaining * 0.5).round(),
                  ),
                  (label: 'Fill Left (${fmt(remaining)})', m: remaining),
                ])
                  if (entry.m > 0)
                    ActionChip(
                      label: Text(entry.label),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        setState(() => _ctrl.text = _minorToPlain(entry.m));
                      },
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
