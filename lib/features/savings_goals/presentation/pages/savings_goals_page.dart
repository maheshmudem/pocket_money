import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/financial_engine/currency.dart';
import '../../../../core/financial_engine/money.dart';
import '../../../../shared/widgets/classic_motion.dart';
import '../../../../shared/widgets/enterprise_layout.dart';
import '../../../../shared/widgets/fintech_widgets.dart';
import '../../../../shared/widgets/flagship_visuals.dart';
import '../../../../shared/widgets/modern_dialogs.dart';
import '../../../../shared/widgets/modern_dropdown.dart';
import '../../../../shared/widgets/modern_inputs.dart';
import '../../../accounts/domain/entities/financial_account_entity.dart';
import '../../../accounts/domain/repositories/account_repository.dart';
import '../../../dashboard/presentation/bloc/dashboard_bloc.dart';
import '../../../notifications/data/financial_alerts_coordinator.dart';
import '../../../profiles/domain/entities/profile_entity.dart';
import '../../../profiles/presentation/bloc/active_profile_cubit.dart';
import '../../../settings/presentation/bloc/settings_cubit.dart';
import '../../../transactions/presentation/bloc/transactions_bloc.dart';
import '../../domain/entities/savings_goal_entity.dart';
import '../../domain/repositories/savings_goal_repository.dart';

/// Covers `SCR-GOAL-001` (Goals Overview) and `SCR-GOAL-002` (Create Goal / Contributions).
class SavingsGoalsPage extends StatefulWidget {
  const SavingsGoalsPage({super.key});

  @override
  State<SavingsGoalsPage> createState() => _SavingsGoalsPageState();
}

class _SavingsGoalsPageState extends State<SavingsGoalsPage> {
  List<SavingsGoalEntity>? _goals;
  bool _loading = true;
  String? _loadedProfileId;

  Future<void> _reload(FinancialProfile profile) async {
    _loadedProfileId = profile.id.value;
    setState(() => _loading = true);
    final res = await GetIt.I<SavingsGoalRepository>().listGoals(profile.id);
    if (!mounted) return;
    setState(() {
      _goals = res.valueOrNull ?? const [];
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
          icon: Icons.savings_outlined,
          title: 'No active profile',
          description: 'Select a profile to track savings goals.',
        ),
      );
    }
    if (_loadedProfileId != profile.id.value) {
      _loadedProfileId = profile.id.value;
      Future.microtask(() => _reload(profile));
    }

    final goals = _goals ?? const [];
    final hasGoals = goals.isNotEmpty;
    final cfo = context.cfoColors;
    final canPost = profile.permissions.canPostTransaction;
    final totalSavedMinor = goals.fold<int>(
      0,
      (s, g) => s + g.contributedAmount.amountMinor,
    );
    final totalTargetMinor = goals.fold<int>(
      0,
      (s, g) => s + g.targetAmount.amountMinor,
    );

    return Scaffold(
      appBar: const EnterpriseAppBar(title: Text('Savings Goals')),
      floatingActionButton: ClassicAnimatedFab(
        child: hasGoals && canPost
            ? FloatingActionButton.extended(
                key: const ValueKey<String>('goals_fab'),
                onPressed: () => _openCreateGoalSheet(context, profile),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New Goal'),
              )
            : null,
      ),
      body: ClassicContentSwitcher(
        stateKey: _loading && _goals == null
            ? 'loading'
            : !hasGoals
            ? 'empty'
            : 'loaded',
        child: _loading && _goals == null
            ? const DashboardSkeletonView()
            : !hasGoals
            ? EmptyStateView(
                icon: Icons.savings_outlined,
                title: 'No savings goals yet',
                description:
                    'Track emergency funds, travel, or capital reserves via ring-fenced allocations or real ledger transfers into a dedicated savings account.',
                actionLabel: canPost ? 'Create Goal' : null,
                onAction: canPost
                    ? () => _openCreateGoalSheet(context, profile)
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
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final twoCols = constraints.maxWidth >= 680;
                        final cardWidth = twoCols
                            ? (constraints.maxWidth - AppSpacing.sm) / 2
                            : constraints.maxWidth;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            StaggeredFadeSlide(
                              index: 0,
                              child: FintechSignatureHero(
                                tone: SignatureHeroTone.emerald,
                                padding: const EdgeInsets.all(AppSpacing.md),
                                child: Row(
                                  children: [
                                    RadialScoreGauge(
                                      score: totalTargetMinor > 0
                                          ? ((totalSavedMinor /
                                                        totalTargetMinor) *
                                                    100)
                                                .round()
                                                .clamp(0, 100)
                                          : 0,
                                      label: 'FUNDED',
                                      activeColor: const Color(0xFF34D399),
                                      secondaryColor: const Color(0xFF38BDF8),
                                      trackColor: Colors.white.withValues(
                                        alpha: 0.14,
                                      ),
                                      textColor: Colors.white,
                                      subtitleColor: Colors.white.withValues(
                                        alpha: 0.70,
                                      ),
                                      size: 80,
                                      strokeWidth: 7,
                                      masked: hideBalances,
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Total Vault Progress (${goals.length})',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                          const SizedBox(height: 4),
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: AnimatedMoneyText(
                                              money: Money(
                                                amountMinor: totalSavedMinor,
                                                currencyCode:
                                                    profile.baseCurrencyCode,
                                              ),
                                              masked: hideBalances,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .headlineSmall
                                                  ?.copyWith(
                                                    color: const Color(
                                                      0xFF6EE7B7,
                                                    ),
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            'Saved ${Money(amountMinor: totalSavedMinor, currencyCode: profile.baseCurrencyCode).format(mask: hideBalances)} of ${Money(amountMinor: totalTargetMinor, currencyCode: profile.baseCurrencyCode).format(mask: hideBalances)}',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.72),
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.sm,
                              children: [
                                for (var idx = 0; idx < goals.length; idx++)
                                  SizedBox(
                                    width: cardWidth,
                                    child: Builder(
                                      builder: (context) {
                                        final g = goals[idx];
                                        final pct = (g.progressRatio * 100)
                                            .round();
                                        final completed =
                                            g.progressRatio >= 1.0;
                                        return StaggeredFadeSlide(
                                          index: idx + 1,
                                          child: PressScaleCard(
                                            padding: const EdgeInsets.all(
                                              AppSpacing.md,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    IconSquircle(
                                                      icon: completed
                                                          ? Icons
                                                                .emoji_events_rounded
                                                          : Icons
                                                                .savings_rounded,
                                                      iconColor: cfo.income,
                                                      backgroundColor:
                                                          cfo.incomeContainer,
                                                      size: 40,
                                                    ),
                                                    const SizedBox(
                                                      width: AppSpacing.sm,
                                                    ),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            g.name,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .textTheme
                                                                    .titleMedium,
                                                          ),
                                                          Text(
                                                            '${g.fundingMode.label}${g.linkedAccountName != null ? ' • ${g.linkedAccountName}' : ''}',
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: Theme.of(context)
                                                                .textTheme
                                                                .bodySmall
                                                                ?.copyWith(
                                                                  color: cfo
                                                                      .subtleText,
                                                                ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    FintechStatusPill(
                                                      label: hideBalances
                                                          ? '••%'
                                                          : (completed
                                                                ? 'Achieved $pct%'
                                                                : '$pct%'),
                                                      showDot: completed,
                                                      foreground: cfo.income,
                                                      background:
                                                          cfo.incomeContainer,
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(
                                                  height: AppSpacing.sm,
                                                ),
                                                AnimatedProgressBar(
                                                  value: hideBalances
                                                      ? 0.0
                                                      : g.progressRatio,
                                                  color: cfo.income,
                                                ),
                                                const SizedBox(
                                                  height: AppSpacing.xs,
                                                ),
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        'Saved: ${g.contributedAmount.format(mask: hideBalances)}',
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodySmall
                                                            ?.copyWith(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Flexible(
                                                      child: Text(
                                                        'Target: ${g.targetAmount.format(mask: hideBalances)}',
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodySmall
                                                            ?.copyWith(
                                                              color: cfo
                                                                  .subtleText,
                                                            ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                if (canPost) ...[
                                                  const SizedBox(
                                                    height: AppSpacing.sm,
                                                  ),
                                                  Align(
                                                    alignment:
                                                        Alignment.centerRight,
                                                    child: FilledButton.tonalIcon(
                                                      onPressed: () =>
                                                          _openContributeSheet(
                                                            context,
                                                            profile,
                                                            g,
                                                          ),
                                                      icon: const Icon(
                                                        Icons
                                                            .add_circle_outline_rounded,
                                                        size: 18,
                                                      ),
                                                      label: const Text(
                                                        'Add Contribution',
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Future<void> _openCreateGoalSheet(
    BuildContext context,
    FinancialProfile profile,
  ) async {
    final accs =
        (await GetIt.I<AccountRepository>().listAccounts(
          profile.id,
        )).valueOrNull ??
        const <FinancialAccountEntity>[];
    if (!context.mounted) return;

    await showEnterpriseModal<void>(
      context: context,
      maxWidth: 500,
      builder: (_) => _CreateGoalSheetBody(
        profile: profile,
        accs: accs,
        onSaved: () => _reload(profile),
      ),
    );
  }

  Future<void> _openContributeSheet(
    BuildContext context,
    FinancialProfile profile,
    SavingsGoalEntity goal,
  ) async {
    final accs =
        (await GetIt.I<AccountRepository>().listAccounts(
          profile.id,
        )).valueOrNull ??
        const <FinancialAccountEntity>[];
    if (!context.mounted) return;

    await showEnterpriseModal<void>(
      context: context,
      maxWidth: 480,
      builder: (_) => _ContributeSheetBody(
        profile: profile,
        goal: goal,
        accs: accs,
        onSaved: () => _reload(profile),
      ),
    );
  }
}

class _CreateGoalSheetBody extends StatefulWidget {
  const _CreateGoalSheetBody({
    required this.profile,
    required this.accs,
    required this.onSaved,
  });

  final FinancialProfile profile;
  final List<FinancialAccountEntity> accs;
  final Future<void> Function() onSaved;

  @override
  State<_CreateGoalSheetBody> createState() => _CreateGoalSheetBodyState();
}

class _CreateGoalSheetBodyState extends State<_CreateGoalSheetBody> {
  final _nameCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();
  var _mode = GoalFundingMode.allocated;
  String? _linkedAccountId;
  String? _errorMsg;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _linkedAccountId = widget.accs.firstOrNull?.id;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final cfo = context.cfoColors;
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
                title: 'Create Savings Goal',
                subtitle: 'Track reserves via allocations or linked transfers.',
                icon: Icons.savings_rounded,
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
              FintechTextField(
                label: 'Goal Name (e.g., Emergency Fund)',
                controller: _nameCtrl,
                leadingIcon: Icons.flag_outlined,
                textCapitalization: TextCapitalization.words,
                showClearButton: true,
                onChanged: (_) => setState(() => _errorMsg = null),
              ),
              const SizedBox(height: AppSpacing.sm),
              FintechTextField(
                label: 'Target Amount (${profile.baseCurrencyCode})',
                controller: _targetCtrl,
                leadingIcon: Icons.payments_outlined,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() => _errorMsg = null),
              ),
              const SizedBox(height: AppSpacing.sm),
              FintechDropdownField<GoalFundingMode>(
                label: 'Accounting Model',
                value: _mode,
                leadingIcon: Icons.savings_outlined,
                options: GoalFundingMode.values
                    .map(
                      (m) => FintechDropdownOption<GoalFundingMode>(
                        value: m,
                        label: m.label,
                        icon: m == GoalFundingMode.accountTransfer
                            ? Icons.swap_horiz_rounded
                            : Icons.flag_outlined,
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _mode = v),
              ),
              if (_mode == GoalFundingMode.accountTransfer &&
                  widget.accs.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                FintechDropdownField<String>(
                  label: 'Destination Savings Account',
                  value: _linkedAccountId,
                  leadingIcon: Icons.account_balance_rounded,
                  options: widget.accs
                      .map(
                        (a) => FintechDropdownOption<String>(
                          value: a.id,
                          label: a.name,
                          subtitle: a.accountType.label,
                          badge: a.currencyCode,
                          icon: Icons.account_balance_wallet_outlined,
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _linkedAccountId = v),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: _saving
                    ? null
                    : () async {
                        if (_nameCtrl.text.trim().isEmpty) {
                          setState(
                            () => _errorMsg = 'Please enter a goal name.',
                          );
                          return;
                        }
                        final curr = CurrencyCatalog.requireByCode(
                          profile.baseCurrencyCode,
                        );
                        final parsed = Money.parseDecimal(
                          _targetCtrl.text,
                          currency: curr,
                        );
                        if (parsed.isFailure ||
                            (parsed.valueOrNull?.amountMinor ?? 0) <= 0) {
                          setState(
                            () => _errorMsg =
                                'Enter a valid positive target amount.',
                          );
                          return;
                        }
                        if (_mode == GoalFundingMode.accountTransfer &&
                            _linkedAccountId == null) {
                          setState(
                            () => _errorMsg =
                                'Add a savings account first for transfer-linked goals.',
                          );
                          return;
                        }
                        setState(() {
                          _saving = true;
                          _errorMsg = null;
                        });

                        final res = await GetIt.I<SavingsGoalRepository>()
                            .createGoal(
                              profileId: profile.id,
                              name: _nameCtrl.text.trim(),
                              targetAmountMinor:
                                  parsed.valueOrNull!.amountMinor,
                              currencyCode: profile.baseCurrencyCode,
                              fundingMode: _mode,
                              linkedAccountId:
                                  _mode == GoalFundingMode.accountTransfer
                                  ? _linkedAccountId
                                  : null,
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
                child: const Text('Create Goal'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContributeSheetBody extends StatefulWidget {
  const _ContributeSheetBody({
    required this.profile,
    required this.goal,
    required this.accs,
    required this.onSaved,
  });

  final FinancialProfile profile;
  final SavingsGoalEntity goal;
  final List<FinancialAccountEntity> accs;
  final Future<void> Function() onSaved;

  @override
  State<_ContributeSheetBody> createState() => _ContributeSheetBodyState();
}

class _ContributeSheetBodyState extends State<_ContributeSheetBody> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  late final List<FinancialAccountEntity> _sourceCandidates;
  String? _sourceAccountId;
  String? _errorMsg;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _sourceCandidates = widget.accs
        .where((a) => a.id != widget.goal.linkedAccountId)
        .toList();
    _sourceAccountId = _sourceCandidates.firstOrNull?.id;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final goal = widget.goal;
    final cfo = context.cfoColors;
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
              EnterpriseModalHeader(
                title: 'Contribute to ${goal.name}',
                subtitle: goal.fundingMode.label,
                icon: Icons.add_circle_outline_rounded,
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
              FintechTextField(
                label: 'Amount (${goal.targetAmount.currencyCode})',
                controller: _amountCtrl,
                leadingIcon: Icons.payments_outlined,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() => _errorMsg = null),
              ),
              if (goal.fundingMode == GoalFundingMode.accountTransfer &&
                  _sourceCandidates.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                FintechDropdownField<String>(
                  label: 'Transfer From Account',
                  value: _sourceAccountId,
                  leadingIcon: Icons.account_balance_wallet_outlined,
                  options: _sourceCandidates
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
                  onChanged: (v) => setState(() => _sourceAccountId = v),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              FintechTextField(
                label: 'Note (optional)',
                controller: _noteCtrl,
                leadingIcon: Icons.notes_rounded,
                showClearButton: true,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: _saving
                    ? null
                    : () async {
                        final curr = CurrencyCatalog.requireByCode(
                          goal.targetAmount.currencyCode,
                        );
                        final parsed = Money.parseDecimal(
                          _amountCtrl.text,
                          currency: curr,
                        );
                        if (parsed.isFailure ||
                            (parsed.valueOrNull?.amountMinor ?? 0) <= 0) {
                          setState(
                            () => _errorMsg =
                                'Enter a valid positive contribution amount.',
                          );
                          return;
                        }
                        setState(() {
                          _saving = true;
                          _errorMsg = null;
                        });
                        final res = await GetIt.I<SavingsGoalRepository>()
                            .recordContribution(
                              profileId: widget.profile.id,
                              goalId: goal.id,
                              amountMinor: parsed.valueOrNull!.amountMinor,
                              sourceAccountId: _sourceAccountId,
                              note: _noteCtrl.text,
                            );
                        if (!context.mounted) return;
                        if (res.isFailure) {
                          setState(() {
                            _saving = false;
                            _errorMsg = res.failureOrNull!.message;
                          });
                          return;
                        }
                        await GetIt.I<FinancialAlertsCoordinator>()
                            .evaluateAfterGoalContribution(widget.profile.id);
                        if (!context.mounted) return;
                        showFintechToast(
                          context,
                          'Contribution saved to ${goal.name}.',
                          tone: FintechToastTone.success,
                        );
                        try {
                          context.read<DashboardBloc>().add(
                            const DashboardRefreshRequested(),
                          );
                        } catch (_) {}
                        try {
                          context.read<TransactionsBloc>().add(
                            const TransactionsLoadRequested(),
                          );
                        } catch (_) {}
                        Navigator.of(context).pop();
                        await widget.onSaved();
                      },
                child: const Text('Save Contribution'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
