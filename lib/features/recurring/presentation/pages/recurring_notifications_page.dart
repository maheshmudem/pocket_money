import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/financial_engine/alert_evaluation_engine.dart';
import '../../../../core/financial_engine/currency.dart';
import '../../../../core/financial_engine/money.dart';
import '../../../../core/utilities/clock.dart';
import '../../../../shared/widgets/enterprise_layout.dart';
import '../../../../shared/widgets/fintech_widgets.dart';
import '../../../../shared/widgets/modern_dialogs.dart';
import '../../../../shared/widgets/modern_dropdown.dart';
import '../../../../shared/widgets/modern_inputs.dart';
import '../../../accounts/domain/entities/financial_account_entity.dart';
import '../../../accounts/domain/repositories/account_repository.dart';
import '../../../categories/domain/entities/category_entity.dart';
import '../../../categories/domain/repositories/category_repository.dart';
import '../../../dashboard/presentation/bloc/dashboard_bloc.dart';
import '../../../notifications/data/financial_alerts_coordinator.dart';
import '../../../profiles/domain/entities/profile_entity.dart';
import '../../../profiles/presentation/bloc/active_profile_cubit.dart';
import '../../../settings/presentation/bloc/settings_cubit.dart';
import '../../../transactions/domain/entities/transaction_entity.dart';
import '../../../transactions/presentation/bloc/transactions_bloc.dart';
import '../../data/repositories/drift_recurring_repository.dart';
import '../../domain/entities/recurring_rule_entity.dart';

enum _NotifFilter { all, unread, budgets, activity }

/// Covers `SCR-REC-001` (Recurring Rules) and `SCR-NOT-001` (Notification Centre).
class RecurringNotificationsPage extends StatefulWidget {
  const RecurringNotificationsPage({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<RecurringNotificationsPage> createState() =>
      _RecurringNotificationsPageState();
}

class _RecurringNotificationsPageState extends State<RecurringNotificationsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  StreamSubscription<dynamic>? _inboxSub;
  List<RecurringRuleEntity>? _rules;
  List<LocalNotificationEntity>? _notifications;
  bool _loading = true;
  String? _loadedProfileId;
  _NotifFilter _notifFilter = _NotifFilter.all;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab,
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _inboxSub = GetIt.I<FinancialAlertsCoordinator>().inboxChanges.listen((
      changedProfileId,
    ) {
      if (!mounted) return;
      final active = context.read<ActiveProfileCubit>().state.activeProfile;
      if (active != null && active.id == changedProfileId) {
        _reload(active);
      }
    });
  }

  @override
  void dispose() {
    _inboxSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _reload(FinancialProfile profile) async {
    _loadedProfileId = profile.id.value;
    final repo = GetIt.I<DriftRecurringRepository>();
    setState(() => _loading = true);
    final rulesRes = await repo.listRules(profile.id);
    final notRes = await repo.listNotifications(profile.id);
    if (!mounted) return;
    setState(() {
      _rules = rulesRes.valueOrNull ?? const [];
      _notifications = notRes.valueOrNull ?? const [];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ActiveProfileCubit>().state.activeProfile;
    final hideBalances = context.watch<SettingsCubit>().state.hideBalances;
    if (profile == null) {
      return const Scaffold(
        body: EmptyStateView(
          icon: Icons.repeat_rounded,
          title: 'No active profile',
          description: 'Select a profile first.',
        ),
      );
    }
    if (_loadedProfileId != profile.id.value) {
      _loadedProfileId = profile.id.value;
      Future.microtask(() => _reload(profile));
    }

    final repo = GetIt.I<DriftRecurringRepository>();
    final rules = _rules ?? const [];
    final items = _notifications ?? const [];
    final cfo = context.cfoColors;
    final canPost = profile.permissions.canPostTransaction;
    final showFab = _tabController.index == 0 && rules.isNotEmpty && canPost;

    return Scaffold(
      appBar: EnterpriseAppBar(
        title: const Text('Recurring & Alerts'),
        actions: [
          if (canPost)
            TextButton.icon(
              onPressed: () async {
                final res = await repo.processDueRules(profile.id);
                final count = res.valueOrNull ?? 0;
                if (context.mounted) {
                  showFintechToast(
                    context,
                    count > 0
                        ? 'Generated $count due occurrence(s) idempotently.'
                        : 'No recurring rules due right now.',
                    tone: count > 0
                        ? FintechToastTone.success
                        : FintechToastTone.info,
                  );
                  context.read<TransactionsBloc>().add(
                    const TransactionsLoadRequested(),
                  );
                  context.read<DashboardBloc>().add(
                    const DashboardRefreshRequested(),
                  );
                }
                await _reload(profile);
              },
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Run Due'),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Recurring Rules'),
            Tab(text: 'Notifications'),
          ],
        ),
      ),
      floatingActionButton: showFab
          ? FloatingActionButton.extended(
              onPressed: () => _openCreateRuleSheet(context, profile, repo),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New Rule'),
            )
          : null,
      body: TabBarView(
        controller: _tabController,
        children: [
          _loading && _rules == null
              ? const DashboardSkeletonView()
              : rules.isEmpty
              ? EmptyStateView(
                  icon: Icons.repeat_rounded,
                  title: 'No recurring rules',
                  description:
                      'Schedule rent, salary, SIPs, or utility bills. Deterministic occurrence keys guarantee zero silent duplicates.',
                  actionLabel: canPost ? 'Create Rule' : null,
                  onAction: canPost
                      ? () => _openCreateRuleSheet(context, profile, repo)
                      : null,
                )
              : RefreshIndicator(
                  onRefresh: () => _reload(profile),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EnterprisePageContainer.responsivePadding(
                      context,
                      bottom: 96,
                    ),
                    child: EnterprisePageContainer(
                      maxWidth: AppBreakpoints.maxContentWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < rules.length; i++) ...[
                            Builder(
                              builder: (context) {
                                final r = rules[i];
                                final isIncome =
                                    r.transactionType == TransactionType.income;
                                return StaggeredFadeSlide(
                                  index: i,
                                  child: PressScaleCard(
                                    padding: const EdgeInsets.all(
                                      AppSpacing.md,
                                    ),
                                    child: Row(
                                      children: [
                                        IconSquircle(
                                          icon: Icons.repeat_rounded,
                                          iconColor: isIncome
                                              ? cfo.income
                                              : cfo.transfer,
                                          backgroundColor: isIncome
                                              ? cfo.incomeContainer
                                              : cfo.transferContainer,
                                          size: 42,
                                        ),
                                        const SizedBox(width: AppSpacing.sm),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                r.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.titleMedium,
                                              ),
                                              Text(
                                                '${r.cadence.label} • Next: ${UiDateFormatter.shortDayMonthYear(r.nextDueAtUtc)} • ${r.autoCreateDraft ? "Draft" : "Auto-Post"}',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: cfo.subtleText,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: AppSpacing.xs),
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxWidth: 108,
                                          ),
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerRight,
                                            child: MoneyText(
                                              money: r.amount,
                                              masked: hideBalances,
                                              semanticKind: isIncome
                                                  ? 'income'
                                                  : null,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Switch(
                                          value: r.status == 'active',
                                          onChanged: canPost
                                              ? (active) async {
                                                  await repo.toggleStatus(
                                                    profile.id,
                                                    r.id,
                                                    active
                                                        ? 'active'
                                                        : 'paused',
                                                  );
                                                  await _reload(profile);
                                                }
                                              : null,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                            if (i < rules.length - 1)
                              const SizedBox(height: AppSpacing.xs),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
          _loading && _notifications == null
              ? const DashboardSkeletonView()
              : _buildNotificationsTab(context, profile, repo, items),
        ],
      ),
    );
  }

  Widget _buildNotificationsTab(
    BuildContext context,
    FinancialProfile profile,
    DriftRecurringRepository repo,
    List<LocalNotificationEntity> items,
  ) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;

    final filtered = items.where((n) {
      final kind = AlertKind.fromWire(n.notificationType);
      return switch (_notifFilter) {
        _NotifFilter.all => true,
        _NotifFilter.unread => !n.isRead,
        _NotifFilter.budgets =>
          kind == AlertKind.budgetWarning80 ||
              kind == AlertKind.budgetReached100 ||
              kind == AlertKind.budgetExceeded ||
              kind == AlertKind.categoryWarning80 ||
              kind == AlertKind.categoryExceeded,
        _NotifFilter.activity =>
          kind == AlertKind.lowBalance ||
              kind == AlertKind.goalMilestone50 ||
              kind == AlertKind.goalCompleted100 ||
              kind == AlertKind.recurringDue ||
              kind == AlertKind.testAlert,
      };
    }).toList();

    final hasUnread = items.any((n) => !n.isRead);
    final hasRead = items.any((n) => n.isRead);
    final unreadCount = items.where((n) => !n.isRead).length;

    return RefreshIndicator(
      onRefresh: () => _reload(profile),
      child: SingleChildScrollView(
        padding: EnterprisePageContainer.responsivePadding(
          context,
          top: 12,
          bottom: 40,
        ),
        child: EnterprisePageContainer(
          maxWidth: AppBreakpoints.maxReadingWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Sliding segmented filter + Alert Settings shortcut
              Row(
                children: [
                  Expanded(
                    child: FintechSegmentedControl<_NotifFilter>(
                      key: const Key('notifications_segmented_filter'),
                      height: 36,
                      selected: _notifFilter,
                      options: [
                        const FintechSegmentOption(
                          value: _NotifFilter.all,
                          label: 'All',
                        ),
                        FintechSegmentOption(
                          value: _NotifFilter.unread,
                          label: 'Unread',
                          badgeCount: unreadCount,
                        ),
                        const FintechSegmentOption(
                          value: _NotifFilter.budgets,
                          label: 'Budgets',
                        ),
                        const FintechSegmentOption(
                          value: _NotifFilter.activity,
                          label: 'Activity',
                        ),
                      ],
                      onChanged: (f) => setState(() => _notifFilter = f),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Alert Preferences',
                    child: Material(
                      color: cfo.surfaceTonal,
                      shape: CircleBorder(
                        side: BorderSide(
                          color: cfo.divider.withValues(alpha: 0.7),
                        ),
                      ),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => context.push('/settings'),
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: Icon(
                            Icons.tune_rounded,
                            size: 17,
                            color: cfo.subtleText,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              if (hasUnread || hasRead) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (hasUnread)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 34),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        onPressed: () async {
                          HapticFeedback.selectionClick();
                          await GetIt.I<FinancialAlertsCoordinator>()
                              .markAllRead(profile.id);
                          await _reload(profile);
                        },
                        icon: const Icon(Icons.done_all_rounded, size: 16),
                        label: const Text('Mark all read'),
                      ),
                    if (hasRead)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 34),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          foregroundColor: cfo.subtleText,
                        ),
                        onPressed: () async {
                          HapticFeedback.selectionClick();
                          await GetIt.I<FinancialAlertsCoordinator>()
                              .clearReadNotifications(profile.id);
                          await _reload(profile);
                        },
                        icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                        label: const Text('Clear read'),
                      ),
                  ],
                ),
              ] else
                const SizedBox(height: 12),

              if (items.isEmpty)
                EmptyStateView(
                  icon: Icons.notifications_none_rounded,
                  title: 'All caught up',
                  description:
                      'Budget limit warnings (80% & 100%+), low-balance alerts, goal milestones, and recurring reminders appear here.',
                  actionLabel: 'Send Test Alert',
                  onAction: () async {
                    await GetIt.I<FinancialAlertsCoordinator>()
                        .sendTestNotification(profile.id);
                    await _reload(profile);
                  },
                )
              else if (filtered.isEmpty)
                PressScaleCard(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    children: [
                      Icon(
                        Icons.filter_list_off_rounded,
                        size: 32,
                        color: cfo.subtleText,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No alerts in this filter',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonal(
                        onPressed: () =>
                            setState(() => _notifFilter = _NotifFilter.all),
                        child: const Text('Show All Alerts'),
                      ),
                    ],
                  ),
                )
              else
                for (var i = 0; i < filtered.length; i++) ...[
                  Builder(
                    builder: (context) {
                      final n = filtered[i];
                      final kind = AlertKind.fromWire(n.notificationType);
                      final (
                        IconData icon,
                        Color fg,
                        Color bg,
                        String tag,
                      ) = switch (kind) {
                        AlertKind.budgetExceeded ||
                        AlertKind.categoryExceeded => (
                          Icons.warning_amber_rounded,
                          cfo.expense,
                          cfo.expenseContainer,
                          'OVER LIMIT',
                        ),
                        AlertKind.budgetReached100 => (
                          Icons.flag_rounded,
                          cfo.warning,
                          cfo.warningContainer,
                          '100% HIT',
                        ),
                        AlertKind.budgetWarning80 ||
                        AlertKind.categoryWarning80 => (
                          Icons.pie_chart_rounded,
                          cfo.warning,
                          cfo.warningContainer,
                          '80% WARN',
                        ),
                        AlertKind.lowBalance => (
                          Icons.account_balance_wallet_outlined,
                          cfo.warning,
                          cfo.warningContainer,
                          'LOW BALANCE',
                        ),
                        AlertKind.goalMilestone50 ||
                        AlertKind.goalCompleted100 => (
                          Icons.emoji_events_rounded,
                          cfo.income,
                          cfo.incomeContainer,
                          'MILESTONE',
                        ),
                        AlertKind.testAlert => (
                          Icons.notifications_active_rounded,
                          scheme.primary,
                          scheme.primaryContainer,
                          'TEST',
                        ),
                        AlertKind.recurringDue => (
                          Icons.repeat_rounded,
                          cfo.transfer,
                          cfo.transferContainer,
                          'RECURRING',
                        ),
                      };

                      return StaggeredFadeSlide(
                        index: i,
                        child: PressScaleCard(
                          borderColor: !n.isRead
                              ? fg.withValues(alpha: 0.35)
                              : null,
                          onTap: () async {
                            HapticFeedback.selectionClick();
                            if (!n.isRead) {
                              await repo.markNotificationRead(profile.id, n.id);
                              await _reload(profile);
                            }
                            final route = n.deepLinkRoute;
                            if (context.mounted &&
                                route != null &&
                                route.isNotEmpty) {
                              context.push(route);
                            }
                          },
                          padding: const EdgeInsets.fromLTRB(13, 12, 12, 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              IconSquircle(
                                icon: icon,
                                iconColor: n.isRead ? cfo.subtleText : fg,
                                backgroundColor: n.isRead
                                    ? cfo.surfaceTonal
                                    : bg,
                                size: 38,
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        FintechStatusPill(
                                          label: tag,
                                          showDot: !n.isRead,
                                          foreground: n.isRead
                                              ? cfo.subtleText
                                              : fg,
                                          background: n.isRead
                                              ? cfo.surfaceTonal
                                              : bg,
                                        ),
                                        const Spacer(),
                                        Text(
                                          UiDateFormatter.shortDayMonth(
                                            n.createdAtUtc,
                                          ),
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
                                    const SizedBox(height: 5),
                                    Text(
                                      n.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: n.isRead
                                                ? FontWeight.w600
                                                : FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      n.body,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: cfo.subtleText,
                                            height: 1.35,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              if (n.deepLinkRoute != null) ...[
                                const SizedBox(width: 4),
                                Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: Icon(
                                    Icons.chevron_right_rounded,
                                    size: 18,
                                    color: cfo.subtleText,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openCreateRuleSheet(
    BuildContext context,
    FinancialProfile profile,
    DriftRecurringRepository repo,
  ) async {
    final accs =
        (await GetIt.I<AccountRepository>().listAccounts(
          profile.id,
        )).valueOrNull ??
        const <FinancialAccountEntity>[];
    final cats =
        (await GetIt.I<CategoryRepository>().listCategories(
          profile.id,
        )).valueOrNull ??
        const <CategoryEntity>[];
    if (!context.mounted) return;
    if (accs.isEmpty) {
      showFintechToast(
        context,
        'Add a financial account first to schedule recurring rules.',
        tone: FintechToastTone.warning,
      );
      return;
    }

    await showEnterpriseModal<void>(
      context: context,
      maxWidth: 500,
      builder: (_) => _CreateRuleSheetBody(
        profile: profile,
        repo: repo,
        accs: accs,
        cats: cats,
        onSaved: () => _reload(profile),
      ),
    );
  }
}

class _CreateRuleSheetBody extends StatefulWidget {
  const _CreateRuleSheetBody({
    required this.profile,
    required this.repo,
    required this.accs,
    required this.cats,
    required this.onSaved,
  });

  final FinancialProfile profile;
  final DriftRecurringRepository repo;
  final List<FinancialAccountEntity> accs;
  final List<CategoryEntity> cats;
  final Future<void> Function() onSaved;

  @override
  State<_CreateRuleSheetBody> createState() => _CreateRuleSheetBodyState();
}

class _CreateRuleSheetBodyState extends State<_CreateRuleSheetBody> {
  final _nameCtrl = TextEditingController();
  final _amtCtrl = TextEditingController();
  var _txType = TransactionType.expense;
  var _cadence = RecurringCadence.monthly;
  late String _accId;
  String? _catId;
  var _asDraft = true;
  String? _errorMsg;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _accId = widget.accs.first.id;
    _catId = _firstCategoryFor(_txType);
  }

  String? _firstCategoryFor(TransactionType type) {
    final targetCatType = type == TransactionType.income
        ? CategoryType.income
        : CategoryType.expense;
    return widget.cats
        .where((c) => c.categoryType == targetCatType)
        .firstOrNull
        ?.id;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amtCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final cfo = context.cfoColors;
    final catType = _txType == TransactionType.income
        ? CategoryType.income
        : CategoryType.expense;
    final filteredCats = widget.cats
        .where((c) => c.categoryType == catType)
        .toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const EnterpriseModalHeader(
                title: 'New Recurring Rule',
                subtitle: 'Idempotent scheduled entries & reminders.',
                icon: Icons.repeat_rounded,
              ),
              if (_errorMsg != null) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: cfo.expenseContainer,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Text(
                    _errorMsg!,
                    style: TextStyle(
                      color: cfo.expense,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              FintechSegmentedControl<TransactionType>(
                selected: _txType,
                options: const [
                  FintechSegmentOption(
                    value: TransactionType.expense,
                    label: 'Expense',
                    icon: Icons.north_east_rounded,
                  ),
                  FintechSegmentOption(
                    value: TransactionType.income,
                    label: 'Income',
                    icon: Icons.south_west_rounded,
                  ),
                ],
                onChanged: (t) => setState(() {
                  _txType = t;
                  _catId = _firstCategoryFor(t);
                }),
              ),
              const SizedBox(height: AppSpacing.sm),
              FintechTextField(
                label: 'Rule Name',
                controller: _nameCtrl,
                leadingIcon: Icons.repeat_rounded,
                textCapitalization: TextCapitalization.words,
                showClearButton: true,
                onChanged: (_) => setState(() => _errorMsg = null),
              ),
              const SizedBox(height: AppSpacing.sm),
              FintechTextField(
                label: 'Amount (${profile.baseCurrencyCode})',
                controller: _amtCtrl,
                leadingIcon: Icons.payments_outlined,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() => _errorMsg = null),
              ),
              const SizedBox(height: AppSpacing.sm),
              FintechDropdownField<RecurringCadence>(
                label: 'Cadence',
                value: _cadence,
                leadingIcon: Icons.repeat_rounded,
                options: RecurringCadence.values
                    .map(
                      (c) => FintechDropdownOption<RecurringCadence>(
                        value: c,
                        label: c.label,
                        icon: Icons.event_repeat_rounded,
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _cadence = v),
              ),
              const SizedBox(height: AppSpacing.sm),
              FintechDropdownField<String>(
                label: 'Account',
                value: _accId,
                leadingIcon: Icons.account_balance_wallet_outlined,
                options: widget.accs
                    .map(
                      (a) => FintechDropdownOption<String>(
                        value: a.id,
                        label: a.name,
                        subtitle: a.accountType.label,
                        badge: a.currencyCode,
                        icon: Icons.account_balance_rounded,
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _accId = v),
              ),
              if (filteredCats.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                FintechDropdownField<String?>(
                  label: 'Category',
                  value: _catId,
                  leadingIcon: Icons.local_offer_outlined,
                  options: filteredCats
                      .map(
                        (c) => FintechDropdownOption<String?>(
                          value: c.id,
                          label: c.name,
                          icon: Icons.local_offer_outlined,
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _catId = v),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              FintechSwitchCard(
                icon: Icons.edit_note_rounded,
                title: 'Create as Draft for review',
                subtitle: 'Review before posting to the immutable ledger',
                value: _asDraft,
                onChanged: (v) => setState(() => _asDraft = v),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: _saving
                    ? null
                    : () async {
                        if (_nameCtrl.text.trim().isEmpty) {
                          setState(
                            () => _errorMsg = 'Please enter a rule name.',
                          );
                          return;
                        }
                        final curr = CurrencyCatalog.requireByCode(
                          profile.baseCurrencyCode,
                        );
                        final parsed = Money.parseDecimal(
                          _amtCtrl.text,
                          currency: curr,
                        );
                        if (parsed.isFailure ||
                            (parsed.valueOrNull?.amountMinor ?? 0) <= 0) {
                          setState(
                            () => _errorMsg =
                                'Enter a valid positive recurring amount.',
                          );
                          return;
                        }
                        setState(() {
                          _saving = true;
                          _errorMsg = null;
                        });

                        final res = await widget.repo.createRule(
                          profileId: profile.id,
                          name: _nameCtrl.text.trim(),
                          transactionType: _txType,
                          amountMinor: parsed.valueOrNull!.amountMinor,
                          currencyCode: profile.baseCurrencyCode,
                          cadence: _cadence,
                          nextDueAtUtc: GetIt.I<UtcClock>().nowIsoUtc(),
                          sourceAccountId: _txType == TransactionType.expense
                              ? _accId
                              : null,
                          destinationAccountId:
                              _txType == TransactionType.income ? _accId : null,
                          categoryId: _catId,
                          autoCreateDraft: _asDraft,
                        );
                        if (!context.mounted) return;
                        if (res.isFailure) {
                          setState(() {
                            _saving = false;
                            _errorMsg = res.failureOrNull!.message;
                          });
                          return;
                        }
                        Navigator.of(context).pop();
                        await widget.onSaved();
                      },
                child: const Text('Save Rule'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
