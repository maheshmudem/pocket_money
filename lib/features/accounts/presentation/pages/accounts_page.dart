import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/financial_engine/currency.dart';
import '../../../../core/financial_engine/fx_rate.dart';
import '../../../../core/financial_engine/money.dart';
import '../../../../core/utilities/clock.dart';
import '../../../../core/utilities/id_generator.dart';
import '../../../../shared/widgets/editorial_bento_kit.dart';
import '../../../../shared/widgets/enterprise_layout.dart';
import '../../../../shared/widgets/fintech_widgets.dart';
import '../../../../shared/widgets/flagship_visuals.dart';
import '../../../../shared/widgets/modern_dialogs.dart';
import '../../../../shared/widgets/modern_dropdown.dart';
import '../../../../shared/widgets/modern_inputs.dart';
import '../../../dashboard/presentation/bloc/dashboard_bloc.dart';
import '../../../profiles/domain/entities/profile_entity.dart';
import '../../../profiles/presentation/bloc/active_profile_cubit.dart';
import '../../../settings/presentation/bloc/settings_cubit.dart';
import '../../../transactions/domain/entities/transaction_entity.dart';
import '../../../transactions/domain/repositories/transaction_repository.dart';
import '../../../transactions/presentation/bloc/transactions_bloc.dart';
import '../../../transactions/presentation/pages/transactions_page.dart';
import '../../domain/entities/financial_account_entity.dart';
import '../../domain/repositories/account_repository.dart';

enum _AccountGroupFilter { all, liquid, credit, investment, archived }

enum _AccountSortOrder {
  balanceDesc('Balance: High → Low'),
  balanceAsc('Balance: Low → High'),
  nameAsc('Name: A → Z');

  const _AccountSortOrder(this.label);
  final String label;
}

/// Covers `SCR-ACC-001` (Account Portfolio, Capital Allocation, Search, Sort & Filters),
/// `SCR-ACC-002` (Add/Edit Account with Opening Balance), and
/// `SCR-ACC-003` (Account Statement Inspector, Inline Edit & Quick Posting).
class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  ProfileId? _watchedProfileId;
  bool _watchedIncludeArchived = false;
  Stream<List<FinancialAccountEntity>>? _accountsStream;
  _AccountGroupFilter _groupFilter = _AccountGroupFilter.all;
  _AccountSortOrder _sortOrder = _AccountSortOrder.balanceDesc;
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Stream<List<FinancialAccountEntity>> _streamFor(
    AccountRepository repo,
    ProfileId profileId,
    bool includeArchived,
  ) {
    if (_watchedProfileId != profileId ||
        _watchedIncludeArchived != includeArchived ||
        _accountsStream == null) {
      _watchedProfileId = profileId;
      _watchedIncludeArchived = includeArchived;
      _accountsStream = repo.watchAccounts(
        profileId,
        includeArchived: includeArchived,
      );
    }
    return _accountsStream!;
  }

  List<FinancialAccountEntity> _applyFilter(List<FinancialAccountEntity> all) {
    final q = _query.trim().toLowerCase();
    final filtered = all.where((a) {
      if (_groupFilter == _AccountGroupFilter.archived) {
        if (!a.isArchived) return false;
      } else {
        if (a.isArchived) return false;
        final matchesGroup = switch (_groupFilter) {
          _AccountGroupFilter.all => true,
          _AccountGroupFilter.liquid =>
            a.accountType == FinancialAccountType.bank ||
                a.accountType == FinancialAccountType.cash ||
                a.accountType == FinancialAccountType.wallet,
          _AccountGroupFilter.credit => a.isLiability,
          _AccountGroupFilter.investment =>
            a.accountType == FinancialAccountType.investment ||
                a.accountType == FinancialAccountType.other,
          _AccountGroupFilter.archived => false,
        };
        if (!matchesGroup) return false;
      }
      if (q.isEmpty) return true;
      return a.name.toLowerCase().contains(q) ||
          a.accountType.label.toLowerCase().contains(q) ||
          a.currencyCode.toLowerCase().contains(q) ||
          (a.institutionLabel?.toLowerCase().contains(q) ?? false);
    }).toList();

    filtered.sort((a, b) {
      return switch (_sortOrder) {
        _AccountSortOrder.balanceDesc => b.baseBalance.amountMinor.compareTo(
          a.baseBalance.amountMinor,
        ),
        _AccountSortOrder.balanceAsc => a.baseBalance.amountMinor.compareTo(
          b.baseBalance.amountMinor,
        ),
        _AccountSortOrder.nameAsc => a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        ),
      };
    });
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ActiveProfileCubit>().state.activeProfile;
    final hideBalances = context.watch<SettingsCubit>().state.hideBalances;

    if (profile == null) {
      return const EmptyStateView(
        icon: Icons.account_balance_outlined,
        title: 'No active profile',
        description: 'Select a profile first to manage financial accounts.',
      );
    }

    final repo = GetIt.I<AccountRepository>();
    final needArchived = _groupFilter == _AccountGroupFilter.archived;

    return AnimatedSwitcher(
      duration: AppMotion.resolve(context, AppMotion.fast),
      child: StreamBuilder<List<FinancialAccountEntity>>(
        key: ValueKey<String>('${profile.id.value}_$needArchived'),
        stream: _streamFor(repo, profile.id, needArchived),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const DashboardSkeletonView();
          }
          final rawAccounts = snapshot.data ?? const [];
          final activeAccounts = rawAccounts
              .where((a) => !a.isArchived)
              .toList();

          if (activeAccounts.isEmpty &&
              _groupFilter != _AccountGroupFilter.archived) {
            return _EmptyAccountsLaunchpad(
              profile: profile,
              onAddAccount: () => _openAddAccountSheet(context, profile),
            );
          }

          final assets = activeAccounts.where((a) => !a.isLiability).toList();
          final liabilities = activeAccounts
              .where((a) => a.isLiability)
              .toList();

          final totalAssetMinor = assets.fold<int>(
            0,
            (sum, a) => sum + a.baseBalance.amountMinor,
          );
          final totalLiabilityMinor = liabilities.fold<int>(
            0,
            (sum, a) => sum + a.baseBalance.amountMinor,
          );
          final netPositionMinor = totalAssetMinor - totalLiabilityMinor;

          final visibleAccounts = _applyFilter(rawAccounts);
          final visibleAssets = visibleAccounts
              .where((a) => !a.isLiability)
              .toList();
          final visibleLiabilities = visibleAccounts
              .where((a) => a.isLiability)
              .toList();

          return RefreshIndicator(
            onRefresh: () async {
              context.read<DashboardBloc>().add(
                const DashboardRefreshRequested(),
              );
              setState(() => _accountsStream = null);
            },
            child: CustomScrollView(
              scrollCacheExtent: const ScrollCacheExtent.pixels(640),
              slivers: [
                SliverPadding(
                  padding: EnterprisePageContainer.responsivePadding(
                    context,
                    top: 10,
                    bottom: 44,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: EnterprisePageContainer(
                      maxWidth: AppBreakpoints.maxContentWidth,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final twoCols = constraints.maxWidth >= 680;
                          final cardWidth = twoCols
                              ? (constraints.maxWidth - AppSpacing.sm) / 2
                              : constraints.maxWidth;
                          final cfo = context.cfoColors;

                          Widget buildSection(
                            String title,
                            List<FinancialAccountEntity> items,
                            int groupTotalMinor,
                            bool isLiabilityGroup,
                            int startIdx,
                          ) {
                            final visibleSum = items.fold<int>(
                              0,
                              (s, a) => s + a.baseBalance.amountMinor,
                            );
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        title,
                                        style: AppTypography.editorial(
                                          context,
                                          fontSize: 19,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 1.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: cfo.surfaceTonal,
                                          borderRadius: BorderRadius.circular(
                                            AppSpacing.radiusFull,
                                          ),
                                        ),
                                        child: Text(
                                          '${items.length}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: cfo.subtleText,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 10,
                                              ),
                                        ),
                                      ),
                                      const Spacer(),
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 140,
                                        ),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerRight,
                                          child: MoneyText(
                                            money: Money(
                                              amountMinor: visibleSum,
                                              currencyCode:
                                                  profile.baseCurrencyCode,
                                            ),
                                            masked: hideBalances,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelMedium
                                                ?.copyWith(
                                                  color: isLiabilityGroup
                                                      ? cfo.expense
                                                      : cfo.subtleText,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: AppSpacing.sm,
                                  runSpacing: 10,
                                  children: [
                                    for (var i = 0; i < items.length; i++)
                                      SizedBox(
                                        width: cardWidth,
                                        child: StaggeredFadeSlide(
                                          index: startIdx + i,
                                          child: _AccountCard(
                                            account: items[i],
                                            profile: profile,
                                            groupTotalMinor: groupTotalMinor,
                                            masked: hideBalances,
                                            onTap: () =>
                                                _openAccountDetailsSheet(
                                                  context,
                                                  profile,
                                                  items[i],
                                                  hideBalances,
                                                  repo,
                                                ),
                                            onArchive: () async {
                                              final target = items[i];
                                              final confirmed =
                                                  await showModernConfirmDialog(
                                                    context: context,
                                                    title:
                                                        'Archive ${target.name}?',
                                                    subtitle:
                                                        'Historical ledger postings remain intact',
                                                    icon:
                                                        Icons.archive_outlined,
                                                    accent: ModernDialogAccent
                                                        .warning,
                                                    confirmLabel: 'Archive',
                                                    message:
                                                        'Archived accounts are hidden from active balances and new entries. You can restore them anytime from the Archived view.',
                                                  );
                                              if (confirmed != true ||
                                                  !context.mounted) {
                                                return;
                                              }
                                              final dashBloc = context
                                                  .read<DashboardBloc>();
                                              await repo.archiveAccount(
                                                profileId: profile.id,
                                                accountId: target.id,
                                              );
                                              if (!context.mounted) return;
                                              dashBloc.add(
                                                const DashboardRefreshRequested(),
                                              );
                                              showFintechToast(
                                                context,
                                                '${target.name} archived.',
                                                tone: FintechToastTone.info,
                                                actionLabel: 'Undo',
                                                onAction: () async {
                                                  await repo.unarchiveAccount(
                                                    profileId: profile.id,
                                                    accountId: target.id,
                                                  );
                                                  dashBloc.add(
                                                    const DashboardRefreshRequested(),
                                                  );
                                                },
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            );
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              StaggeredFadeSlide(
                                index: 0,
                                child: _PortfolioHeaderCard(
                                  profile: profile,
                                  accounts: activeAccounts,
                                  netPosition: Money(
                                    amountMinor: netPositionMinor,
                                    currencyCode: profile.baseCurrencyCode,
                                  ),
                                  totalAssets: Money(
                                    amountMinor: totalAssetMinor,
                                    currencyCode: profile.baseCurrencyCode,
                                  ),
                                  totalLiabilities: Money(
                                    amountMinor: totalLiabilityMinor,
                                    currencyCode: profile.baseCurrencyCode,
                                  ),
                                  masked: hideBalances,
                                  canAdd:
                                      profile.permissions.canPostTransaction,
                                  onAddTap: () =>
                                      _openAddAccountSheet(context, profile),
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Ultra-compact Search + Sort + Sliding Segmented Filter
                              _AccountsFilterToolbar(
                                searchCtrl: _searchCtrl,
                                query: _query,
                                selectedGroup: _groupFilter,
                                sortOrder: _sortOrder,
                                onQueryChanged: (v) =>
                                    setState(() => _query = v),
                                onClearQuery: () {
                                  _searchCtrl.clear();
                                  setState(() => _query = '');
                                },
                                onGroupSelected: (g) =>
                                    setState(() => _groupFilter = g),
                                onSortSelected: (s) =>
                                    setState(() => _sortOrder = s),
                              ),
                              const SizedBox(height: 14),

                              if (visibleAccounts.isEmpty)
                                PressScaleCard(
                                  padding: const EdgeInsets.all(AppSpacing.xl),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.filter_list_off_rounded,
                                        size: 34,
                                        color: cfo.subtleText,
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        _groupFilter ==
                                                _AccountGroupFilter.archived
                                            ? 'No archived accounts'
                                            : 'No accounts match your filter',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Reset search or category filters to view all active accounts.',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(color: cfo.subtleText),
                                      ),
                                      const SizedBox(height: AppSpacing.sm),
                                      FilledButton.tonal(
                                        onPressed: () {
                                          _searchCtrl.clear();
                                          setState(() {
                                            _query = '';
                                            _groupFilter =
                                                _AccountGroupFilter.all;
                                          });
                                        },
                                        child: const Text(
                                          'Show All Active Accounts',
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else ...[
                                if (visibleAssets.isNotEmpty) ...[
                                  buildSection(
                                    _groupFilter == _AccountGroupFilter.archived
                                        ? 'Archived Assets'
                                        : 'Assets',
                                    visibleAssets,
                                    totalAssetMinor.abs(),
                                    false,
                                    1,
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                if (visibleLiabilities.isNotEmpty)
                                  buildSection(
                                    _groupFilter == _AccountGroupFilter.archived
                                        ? 'Archived Liabilities'
                                        : 'Liabilities',
                                    visibleLiabilities,
                                    totalLiabilityMinor.abs(),
                                    true,
                                    visibleAssets.length + 1,
                                  ),
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openAccountDetailsSheet(
    BuildContext context,
    FinancialProfile profile,
    FinancialAccountEntity account,
    bool masked,
    AccountRepository repo,
  ) async {
    final dashBloc = context.read<DashboardBloc>();
    final txBloc = context.read<TransactionsBloc>();

    await showEnterpriseModal<void>(
      context: context,
      maxWidth: 540,
      builder: (_) => _AccountInspectorModal(
        parentContext: context,
        profile: profile,
        account: account,
        masked: masked,
        accountRepository: repo,
        dashboardBloc: dashBloc,
        transactionsBloc: txBloc,
      ),
    );
  }

  Future<void> _openAddAccountSheet(
    BuildContext context,
    FinancialProfile profile,
  ) => openAddAccountModal(context, profile);
}

/// First-run structured empty state on AccountsPage with quick account-type presets.
class _EmptyAccountsLaunchpad extends StatelessWidget {
  const _EmptyAccountsLaunchpad({
    required this.profile,
    required this.onAddAccount,
  });

  final FinancialProfile profile;
  final VoidCallback onAddAccount;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final canPost = profile.permissions.canPostTransaction;

    final templates = [
      (
        icon: Icons.account_balance_rounded,
        label: 'Savings / Checking',
        type: FinancialAccountType.bank,
        suggested: 'Primary Bank',
        fg: scheme.primary,
        bg: scheme.primaryContainer,
      ),
      (
        icon: Icons.payments_rounded,
        label: 'Physical Cash',
        type: FinancialAccountType.cash,
        suggested: 'Cash in Hand',
        fg: cfo.income,
        bg: cfo.incomeContainer,
      ),
      (
        icon: Icons.credit_card_rounded,
        label: 'Credit Card',
        type: FinancialAccountType.creditCard,
        suggested: 'Rewards Card',
        fg: cfo.expense,
        bg: cfo.expenseContainer,
      ),
      (
        icon: Icons.trending_up_rounded,
        label: 'Investments',
        type: FinancialAccountType.investment,
        suggested: 'Brokerage / Portfolio',
        fg: cfo.transfer,
        bg: cfo.transferContainer,
      ),
    ];

    return SingleChildScrollView(
      padding: EnterprisePageContainer.responsivePadding(context),
      child: EnterprisePageContainer(
        maxWidth: 680,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PressScaleCard(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                children: [
                  IconSquircle(
                    icon: Icons.account_balance_wallet_outlined,
                    iconColor: scheme.primary,
                    backgroundColor: scheme.primaryContainer,
                    size: 56,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'No financial accounts yet',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Add cash, bank, wallet, credit card, or investment accounts. Opening balances post cleanly to Opening Balance Equity.',
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: cfo.subtleText),
                  ),
                  if (canPost) ...[
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton.icon(
                      onPressed: onAddAccount,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add Account'),
                    ),
                  ],
                ],
              ),
            ),
            if (canPost) ...[
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader(
                title: 'Quick Account Templates',
                subtitle: 'Choose an account class to pre-fill setup',
              ),
              const SizedBox(height: AppSpacing.xs),
              LayoutBuilder(
                builder: (context, constraints) {
                  final cols = constraints.maxWidth >= 520 ? 2 : 1;
                  final gap = AppSpacing.sm;
                  final w = (constraints.maxWidth - (cols - 1) * gap) / cols;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final t in templates)
                        SizedBox(
                          width: w,
                          child: PressScaleCard(
                            onTap: () => openAddAccountModal(
                              context,
                              profile,
                              initialType: t.type,
                              suggestedName: t.suggested,
                            ),
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Row(
                              children: [
                                IconSquircle(
                                  icon: t.icon,
                                  iconColor: t.fg,
                                  backgroundColor: t.bg,
                                  size: 40,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        t.label,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleSmall,
                                      ),
                                      Text(
                                        'Base ${profile.baseCurrencyCode} or foreign FX',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(color: cfo.subtleText),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: cfo.subtleText,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AccountsFilterToolbar extends StatelessWidget {
  const _AccountsFilterToolbar({
    required this.searchCtrl,
    required this.query,
    required this.selectedGroup,
    required this.sortOrder,
    required this.onQueryChanged,
    required this.onClearQuery,
    required this.onGroupSelected,
    required this.onSortSelected,
  });

  final TextEditingController searchCtrl;
  final String query;
  final _AccountGroupFilter selectedGroup;
  final _AccountSortOrder sortOrder;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClearQuery;
  final ValueChanged<_AccountGroupFilter> onGroupSelected;
  final ValueChanged<_AccountSortOrder> onSortSelected;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final duration = AppMotion.resolve(context, AppMotion.fast);
    final isArchivedActive = selectedGroup == _AccountGroupFilter.archived;
    final isCustomSort = sortOrder != _AccountSortOrder.balanceDesc;

    const segments = [
      (_AccountGroupFilter.all, 'All'),
      (_AccountGroupFilter.liquid, 'Bank & Cash'),
      (_AccountGroupFilter.credit, 'Credit'),
      (_AccountGroupFilter.investment, 'Invest'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Row 1: Compact pill search + Sort menu button
        Row(
          children: [
            Expanded(
              child: FintechSearchField(
                controller: searchCtrl,
                hintText: 'Search accounts...',
                height: 40,
                elevated: true,
                onChanged: onQueryChanged,
                onClear: onClearQuery,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isCustomSort
                    ? scheme.primaryContainer
                    : cfo.surfaceElevated,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isCustomSort
                      ? scheme.primary.withValues(alpha: 0.4)
                      : cfo.divider,
                ),
              ),
              child: PopupMenuButton<_AccountSortOrder>(
                key: const Key('accounts_sort_btn'),
                tooltip: 'Sort accounts',
                padding: EdgeInsets.zero,
                icon: Icon(
                  Icons.swap_vert_rounded,
                  size: 19,
                  color: isCustomSort ? scheme.primary : cfo.subtleText,
                ),
                onSelected: (next) {
                  HapticFeedback.selectionClick();
                  onSortSelected(next);
                },
                itemBuilder: (_) => [
                  for (final order in _AccountSortOrder.values)
                    PopupMenuItem<_AccountSortOrder>(
                      value: order,
                      child: Row(
                        children: [
                          Icon(
                            sortOrder == order
                                ? Icons.check_rounded
                                : Icons.sort_rounded,
                            size: 16,
                            color: sortOrder == order
                                ? scheme.primary
                                : cfo.subtleText,
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              order.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: sortOrder == order
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Row 2: Single-row sliding segmented filter + compact Archived toggle
        Row(
          children: [
            Expanded(
              child: Container(
                key: const Key('accounts_segmented_filter'),
                height: 36,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: cfo.surfaceTonal,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  border: Border.all(color: cfo.divider.withValues(alpha: 0.7)),
                ),
                child: Row(
                  children: [
                    for (final seg in segments)
                      Expanded(
                        flex: seg.$1 == _AccountGroupFilter.liquid ? 3 : 2,
                        child: Builder(
                          builder: (context) {
                            final active = selectedGroup == seg.$1;
                            final isDark =
                                Theme.of(context).brightness == Brightness.dark;
                            final activeBg = isDark
                                ? const Color(0xFFF4F6FA)
                                : const Color(0xFF0F172A);
                            final activeFg = isDark
                                ? const Color(0xFF0B0D14)
                                : Colors.white;
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                onGroupSelected(seg.$1);
                              },
                              child: AnimatedContainer(
                                duration: duration,
                                curve: Curves.easeOutCubic,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: active ? activeBg : Colors.transparent,
                                  borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusFull,
                                  ),
                                  boxShadow: active
                                      ? [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: isDark ? 0.28 : 0.14,
                                            ),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      seg.$2,
                                      maxLines: 1,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: active
                                                ? activeFg
                                                : cfo.subtleText,
                                            fontWeight: active
                                                ? FontWeight.w800
                                                : FontWeight.w600,
                                          ),
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
            const SizedBox(width: 8),
            Tooltip(
              message: isArchivedActive
                  ? 'Showing archived accounts'
                  : 'Archived accounts',
              child: Material(
                key: const Key('accounts_archived_toggle'),
                color: isArchivedActive
                    ? scheme.primaryContainer
                    : cfo.surfaceTonal,
                shape: CircleBorder(
                  side: BorderSide(
                    color: isArchivedActive
                        ? scheme.primary.withValues(alpha: 0.45)
                        : cfo.divider.withValues(alpha: 0.7),
                  ),
                ),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onGroupSelected(
                      isArchivedActive
                          ? _AccountGroupFilter.all
                          : _AccountGroupFilter.archived,
                    );
                  },
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(
                      isArchivedActive
                          ? Icons.inventory_2_rounded
                          : Icons.inventory_2_outlined,
                      size: 17,
                      color: isArchivedActive ? scheme.primary : cfo.subtleText,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Reusable `SCR-ACC-002` modal for creating a financial account from Accounts or Dashboard.
Future<void> openAddAccountModal(
  BuildContext context,
  FinancialProfile profile, {
  FinancialAccountType initialType = FinancialAccountType.bank,
  String suggestedName = '',
}) async {
  final dashBloc = context.read<DashboardBloc>();
  await showEnterpriseModal<void>(
    context: context,
    maxWidth: 520,
    builder: (_) => _AddAccountModalSheet(
      profile: profile,
      dashboardBloc: dashBloc,
      initialType: initialType,
      suggestedName: suggestedName,
    ),
  );
}

class _AddAccountModalSheet extends StatefulWidget {
  const _AddAccountModalSheet({
    required this.profile,
    required this.dashboardBloc,
    this.initialType = FinancialAccountType.bank,
    this.suggestedName = '',
  });

  final FinancialProfile profile;
  final DashboardBloc dashboardBloc;
  final FinancialAccountType initialType;
  final String suggestedName;

  @override
  State<_AddAccountModalSheet> createState() => _AddAccountModalSheetState();
}

class _AddAccountModalSheetState extends State<_AddAccountModalSheet> {
  late final TextEditingController _nameCtrl;
  final _institutionCtrl = TextEditingController();
  final _openingCtrl = TextEditingController(text: '0');
  final _fxRateCtrl = TextEditingController();
  late FinancialAccountType _accType;
  late String _currCode;
  String? _errorMsg;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.suggestedName);
    _accType = widget.initialType;
    _currCode = widget.profile.baseCurrencyCode;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _institutionCtrl.dispose();
    _openingCtrl.dispose();
    _fxRateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final needsFx = _currCode != profile.baseCurrencyCode;

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
                title: 'Add Financial Account',
                subtitle:
                    'Opening balance generates an Opening Balance Equity ledger entry.',
                icon: Icons.account_balance_wallet_rounded,
              ),
              if (_errorMsg != null) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: context.cfoColors.expenseContainer,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Text(
                    _errorMsg!,
                    style: TextStyle(color: context.cfoColors.expense),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              FintechTextField(
                label: 'Account Name (e.g., HDFC Savings, Cash)',
                controller: _nameCtrl,
                leadingIcon: Icons.account_balance_wallet_outlined,
                textCapitalization: TextCapitalization.words,
                showClearButton: true,
              ),
              const SizedBox(height: AppSpacing.sm),
              FintechDropdownField<FinancialAccountType>(
                key: const Key('account_type_dropdown'),
                label: 'Account Type',
                value: _accType,
                leadingIcon: Icons.account_balance_wallet_outlined,
                options: FinancialAccountType.values
                    .map(
                      (t) => FintechDropdownOption<FinancialAccountType>(
                        value: t,
                        label: t.label,
                        subtitle: t.isLiability
                            ? 'Liability ledger'
                            : 'Asset vault',
                        badge: t.isLiability ? 'Debt' : 'Asset',
                        icon: switch (t) {
                          FinancialAccountType.bank =>
                            Icons.account_balance_rounded,
                          FinancialAccountType.cash => Icons.payments_outlined,
                          FinancialAccountType.wallet =>
                            Icons.account_balance_wallet_rounded,
                          FinancialAccountType.creditCard =>
                            Icons.credit_card_rounded,
                          FinancialAccountType.investment =>
                            Icons.trending_up_rounded,
                          FinancialAccountType.loan =>
                            Icons.request_quote_outlined,
                          FinancialAccountType.other => Icons.savings_outlined,
                        },
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _accType = v),
              ),
              const SizedBox(height: AppSpacing.sm),
              FintechDropdownField<String>(
                key: const Key('account_currency_dropdown'),
                label: 'Currency',
                value: _currCode,
                leadingIcon: Icons.currency_exchange_rounded,
                searchable: true,
                searchHint: 'Search currency...',
                options: FintechDropdownOption.builtInCurrencies(),
                onChanged: (v) => setState(() => _currCode = v),
              ),
              const SizedBox(height: AppSpacing.sm),
              FintechTextField(
                label: _accType.isLiability
                    ? 'Opening Balance Owed ($_currCode)'
                    : 'Opening Balance ($_currCode)',
                helperText:
                    'Creates a balanced Opening Balance Equity journal entry.',
                controller: _openingCtrl,
                leadingIcon: Icons.payments_outlined,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final preset in ['0', '5000', '25000', '100000'])
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: Text('$_currCode $preset'),
                      onPressed: () =>
                          setState(() => _openingCtrl.text = preset),
                    ),
                ],
              ),
              if (needsFx) ...[
                const SizedBox(height: AppSpacing.sm),
                FintechTextField(
                  label:
                      'FX Rate (1 $_currCode = ? ${profile.baseCurrencyCode})',
                  helperText:
                      'Required if opening balance > 0 in non-base currency.',
                  controller: _fxRateCtrl,
                  leadingIcon: Icons.currency_exchange_rounded,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              FintechTextField(
                label: 'Institution Label (optional)',
                controller: _institutionCtrl,
                leadingIcon: Icons.business_outlined,
                textCapitalization: TextCapitalization.words,
                showClearButton: true,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: _submitting
                    ? null
                    : () async {
                        final currSpec = CurrencyCatalog.requireByCode(
                          _currCode,
                        );
                        final parsedOpening = Money.parseDecimal(
                          _openingCtrl.text.trim().isEmpty
                              ? '0'
                              : _openingCtrl.text,
                          currency: currSpec,
                          allowZero: true,
                        );
                        if (parsedOpening.isFailure) {
                          setState(
                            () => _errorMsg =
                                parsedOpening.failureOrNull!.message,
                          );
                          return;
                        }
                        final openingMinor =
                            parsedOpening.valueOrNull!.amountMinor;

                        FxRate? fxRate;
                        if (needsFx && openingMinor > 0) {
                          final parsedFx = FxRate.parseDecimalRate(
                            rawRate: _fxRateCtrl.text,
                            fromCurrencyCode: _currCode,
                            toCurrencyCode: profile.baseCurrencyCode,
                            source: 'manual',
                            effectiveAtUtc: GetIt.I<UtcClock>().nowIsoUtc(),
                          );
                          if (parsedFx.isFailure) {
                            setState(
                              () => _errorMsg = parsedFx.failureOrNull!.message,
                            );
                            return;
                          }
                          fxRate = parsedFx.valueOrNull;
                        }

                        setState(() {
                          _submitting = true;
                          _errorMsg = null;
                        });
                        final nav = Navigator.of(context);
                        final res = await GetIt.I<AccountRepository>()
                            .createAccountWithOpeningBalance(
                              profileId: profile.id,
                              name: _nameCtrl.text,
                              accountType: _accType,
                              currencyCode: _currCode,
                              openingBalanceMinor: openingMinor,
                              openingFxRate: fxRate,
                              institutionLabel:
                                  _institutionCtrl.text.trim().isEmpty
                                  ? null
                                  : _institutionCtrl.text.trim(),
                            );
                        if (!mounted) return;
                        if (res.isFailure) {
                          setState(() {
                            _submitting = false;
                            _errorMsg = res.failureOrNull!.message;
                          });
                          return;
                        }
                        nav.pop();
                        widget.dashboardBloc.add(
                          const DashboardRefreshRequested(),
                        );
                      },
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save Account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _accountIcon(FinancialAccountType type) => switch (type) {
  FinancialAccountType.cash => Icons.payments_rounded,
  FinancialAccountType.bank => Icons.account_balance_rounded,
  FinancialAccountType.wallet => Icons.account_balance_wallet_rounded,
  FinancialAccountType.creditCard => Icons.credit_card_rounded,
  FinancialAccountType.loan => Icons.request_quote_rounded,
  FinancialAccountType.investment => Icons.trending_up_rounded,
  FinancialAccountType.other => Icons.savings_rounded,
};

(Color fg, Color bg) _accountAccent(
  FinancialAccountType type,
  PocketCfoColors cfo,
  ColorScheme scheme,
) => switch (type) {
  FinancialAccountType.bank => (scheme.primary, scheme.primaryContainer),
  FinancialAccountType.cash => (cfo.income, cfo.incomeContainer),
  FinancialAccountType.wallet => (cfo.transfer, cfo.transferContainer),
  FinancialAccountType.investment ||
  FinancialAccountType.other => (scheme.tertiary, scheme.tertiaryContainer),
  FinancialAccountType.creditCard ||
  FinancialAccountType.loan => (cfo.expense, cfo.expenseContainer),
};

/// Open-Canvas Editorial Treasury Header with Monumental Net Position,
/// Live Multi-Segment Asset Allocation Donut Ring, Hairline Assets/Liabilities
/// strip, and compact Quick-Action pills — letting the physical Metallic Vault
/// Cards below command the visual centerpiece without duplicate dark slabs.
class _PortfolioHeaderCard extends StatelessWidget {
  const _PortfolioHeaderCard({
    required this.profile,
    required this.accounts,
    required this.netPosition,
    required this.totalAssets,
    required this.totalLiabilities,
    required this.masked,
    required this.canAdd,
    required this.onAddTap,
  });

  final FinancialProfile profile;
  final List<FinancialAccountEntity> accounts;
  final Money netPosition;
  final Money totalAssets;
  final Money totalLiabilities;
  final bool masked;
  final bool canAdd;
  final VoidCallback onAddTap;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    int liquidMinor = 0;
    int walletMinor = 0;
    int investMinor = 0;
    int debtMinor = 0;
    for (final a in accounts) {
      final absVal = a.baseBalance.amountMinor.abs();
      if (a.isLiability) {
        debtMinor += absVal;
      } else if (a.accountType == FinancialAccountType.wallet) {
        walletMinor += absVal;
      } else if (a.accountType == FinancialAccountType.investment ||
          a.accountType == FinancialAccountType.other) {
        investMinor += absVal;
      } else {
        liquidMinor += absVal;
      }
    }
    final grossVolume = liquidMinor + walletMinor + investMinor + debtMinor;

    final (
      String solvencyLabel,
      Color solvencyFg,
      Color solvencyBg,
    ) = debtMinor == 0
        ? ('Debt-Free Portfolio', cfo.income, cfo.incomeContainer)
        : (totalAssets.amountMinor >= totalLiabilities.amountMinor * 2
              ? ('Strong Solvency', cfo.income, cfo.incomeContainer)
              : ('Monitor Leverage', cfo.warning, cfo.warningContainer));

    final segPalette = [
      if (liquidMinor > 0)
        (label: 'Bank & Cash', val: liquidMinor, color: scheme.primary),
      if (walletMinor > 0)
        (label: 'Wallets', val: walletMinor, color: cfo.transfer),
      if (investMinor > 0)
        (label: 'Investments', val: investMinor, color: scheme.secondary),
      if (debtMinor > 0)
        (label: 'Liabilities', val: debtMinor, color: cfo.expense),
    ];

    final quickActions = [
      (
        icon: Icons.swap_horiz_rounded,
        label: 'Transfer',
        color: cfo.transfer,
        onTap: () => openAddTransactionSheet(
          context,
          profile,
          initialType: TransactionType.transfer,
        ),
      ),
      (
        icon: Icons.south_west_rounded,
        label: 'Deposit',
        color: cfo.income,
        onTap: () => openAddTransactionSheet(
          context,
          profile,
          initialType: TransactionType.income,
        ),
      ),
      (
        icon: Icons.north_east_rounded,
        label: 'Spend',
        color: cfo.expense,
        onTap: () => openAddTransactionSheet(
          context,
          profile,
          initialType: TransactionType.expense,
        ),
      ),
      (
        icon: Icons.add_card_rounded,
        label: 'New Vault',
        color: scheme.secondary,
        onTap: onAddTap,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Row 1: Editorial Title + Debt-Free Badge + Gradient + Add CTA
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Portfolio Overview',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.editorial(
                      context,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  FintechStatusPill(
                    label: solvencyLabel,
                    showDot: true,
                    foreground: solvencyFg,
                    background: solvencyBg,
                  ),
                ],
              ),
            ),
            if (canAdd) ...[
              const SizedBox(width: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFFF4F6FA)
                      : const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(
                        0xFF0F172A,
                      ).withValues(alpha: isDark ? 0.32 : 0.16),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Material(
                  key: const Key('accounts_add_btn'),
                  color: Colors.transparent,
                  shape: const StadiumBorder(),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onAddTap();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add_rounded,
                            size: 16,
                            color: isDark
                                ? const Color(0xFF0B0D14)
                                : Colors.white,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'Add',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: isDark
                                      ? const Color(0xFF0B0D14)
                                      : Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),

        // Row 2: Monumental Open-Canvas Net Position + Live Asset Mix Donut Ring
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 7,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Net Position',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: cfo.subtleText,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: cfo.surfaceTonal,
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusFull,
                          ),
                          border: Border.all(color: cfo.divider),
                        ),
                        child: Text(
                          '${accounts.length} active • ${profile.baseCurrencyCode}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: cfo.subtleText,
                                fontWeight: FontWeight.w800,
                                fontSize: 10,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: AnimatedMoneyText(
                      money: netPosition,
                      masked: masked,
                      semanticContextLabel: 'Net position',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.1,
                        height: 1.05,
                        color: netPosition.amountMinor >= 0
                            ? scheme.onSurface
                            : cfo.expense,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            AssetAllocationDonut(
              slices: [
                for (final seg in segPalette)
                  AllocationDonutSlice(value: seg.val, color: seg.color),
              ],
              centerValue: '${accounts.length}',
              centerCaption: accounts.length == 1 ? 'VAULT' : 'VAULTS',
              size: 74,
              masked: masked,
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Row 3: Dual Tactile Mini-Wells (Assets vs Liabilities) + Allocation Legend
        Row(
          children: [
            Expanded(
              child: TactileColorBlock(
                accent: cfo.income,
                borderRadius: 16,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: _InlinePortfolioStat(
                  label: 'Total Assets',
                  money: totalAssets,
                  masked: masked,
                  icon: Icons.trending_up_rounded,
                  color: cfo.income,
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: TactileColorBlock(
                accent: totalLiabilities.amountMinor > 0
                    ? cfo.expense
                    : scheme.primary,
                borderRadius: 16,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: _InlinePortfolioStat(
                  label: 'Total Liabilities',
                  money: totalLiabilities,
                  masked: masked,
                  icon: Icons.credit_card_rounded,
                  color: totalLiabilities.amountMinor > 0
                      ? cfo.expense
                      : cfo.subtleText,
                ),
              ),
            ),
          ],
        ),

        if (segPalette.isNotEmpty && grossVolume > 0 && !masked) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final seg in segPalette)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: seg.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${seg.label} ${((seg.val / grossVolume) * 100).round()}%',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cfo.subtleText,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],

        if (canAdd) ...[
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < quickActions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Material(
                    color: cfo.surfaceElevated,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusFull,
                      ),
                      side: BorderSide(color: cfo.divider, width: 1.0),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusFull,
                      ),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        quickActions[i].onTap();
                      },
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(7, 6, 12, 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: quickActions[i].color.withValues(
                                  alpha: isDark ? 0.20 : 0.12,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                quickActions[i].icon,
                                size: 13.5,
                                color: quickActions[i].color,
                              ),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              quickActions[i].label,
                              maxLines: 1,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _InlinePortfolioStat extends StatelessWidget {
  const _InlinePortfolioStat({
    required this.label,
    required this.money,
    required this.masked,
    required this.icon,
    required this.color,
  });

  final String label;
  final Money money;
  final bool masked;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cfo.subtleText,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: AnimatedMoneyText(
            money: money,
            masked: masked,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.account,
    required this.profile,
    required this.groupTotalMinor,
    required this.masked,
    required this.onTap,
    required this.onArchive,
  });

  final FinancialAccountEntity account;
  final FinancialProfile profile;
  final int groupTotalMinor;
  final bool masked;
  final VoidCallback onTap;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final baseCurrency = profile.baseCurrencyCode;
    final canPost =
        profile.permissions.canPostTransaction && !account.isArchived;

    final share = groupTotalMinor > 0
        ? (account.baseBalance.amountMinor.abs() / groupTotalMinor).clamp(
            0.0,
            1.0,
          )
        : 0.0;
    final sharePct = (share * 100).round();

    return VirtualAccountVaultCard(
      account: account,
      baseCurrency: baseCurrency,
      sharePercent: sharePct,
      masked: masked,
      onTap: onTap,
      trailingMenu: PopupMenuButton<String>(
        tooltip: 'Account options',
        iconSize: 19,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        icon: Icon(
          Icons.more_vert_rounded,
          color: Colors.white.withValues(alpha: 0.80),
        ),
        onSelected: (v) async {
          if (v == 'inspect') onTap();
          if (v == 'copy') {
            final spec = CurrencyCatalog.byCode(account.currencyCode);
            final formatted = account.balance.format(spec: spec);
            await Clipboard.setData(ClipboardData(text: formatted));
            if (!context.mounted) return;
            HapticFeedback.lightImpact();
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  content: Text('Copied ${account.name} balance ($formatted)'),
                ),
              );
          }
          if (v == 'archive') onArchive();
        },
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: 'inspect',
            child: Row(
              children: [
                Icon(Icons.receipt_long_rounded, size: 17),
                SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'Statement & Edit',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'copy',
            child: Row(
              children: [
                Icon(Icons.copy_rounded, size: 17),
                SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'Copy Balance',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          if (!account.isArchived)
            const PopupMenuItem(
              value: 'archive',
              child: Row(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 17),
                  SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'Archive account',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      bottomBar: canPost
          ? HeroGlassActionBar(
              verticalPadding: 10,
              items: [
                FintechFlatActionItem(
                  icon: Icons.north_east_rounded,
                  label: 'Spend',
                  color: const Color(0xFFFDA4AF),
                  onTap: () => openAddTransactionSheet(
                    context,
                    profile,
                    initialType: TransactionType.expense,
                    initialSourceAccountId: account.id,
                  ),
                ),
                FintechFlatActionItem(
                  icon: Icons.south_west_rounded,
                  label: 'Receive',
                  color: const Color(0xFF6EE7B7),
                  onTap: () => openAddTransactionSheet(
                    context,
                    profile,
                    initialType: TransactionType.income,
                    initialSourceAccountId: account.id,
                  ),
                ),
                FintechFlatActionItem(
                  icon: Icons.swap_horiz_rounded,
                  label: 'Transfer',
                  color: const Color(0xFF93C5FD),
                  onTap: () => openAddTransactionSheet(
                    context,
                    profile,
                    initialType: TransactionType.transfer,
                    initialSourceAccountId: account.id,
                  ),
                ),
                FintechFlatActionItem(
                  icon: Icons.receipt_long_rounded,
                  label: 'Activity',
                  color: const Color(0xFF7DD3FC),
                  onTap: onTap,
                ),
              ],
            )
          : null,
    );
  }
}

/// Complete `SCR-ACC-003` Account Statement Inspector, Quick Posting & Inline Edit Modal.
class _AccountInspectorModal extends StatefulWidget {
  const _AccountInspectorModal({
    required this.parentContext,
    required this.profile,
    required this.account,
    required this.masked,
    required this.accountRepository,
    required this.dashboardBloc,
    required this.transactionsBloc,
  });

  final BuildContext parentContext;
  final FinancialProfile profile;
  final FinancialAccountEntity account;
  final bool masked;
  final AccountRepository accountRepository;
  final DashboardBloc dashboardBloc;
  final TransactionsBloc transactionsBloc;

  @override
  State<_AccountInspectorModal> createState() => _AccountInspectorModalState();
}

class _AccountInspectorModalState extends State<_AccountInspectorModal> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _instCtrl;
  late final Future<List<TransactionEntity>> _recentFuture;
  bool _editing = false;
  bool _savingEdit = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.account.name);
    _instCtrl = TextEditingController(
      text: widget.account.institutionLabel ?? '',
    );
    _recentFuture = _loadRecent();
  }

  Future<List<TransactionEntity>> _loadRecent() async {
    final res = await GetIt.I<TransactionRepository>().queryTransactions(
      widget.profile.id,
      filter: TransactionFilter(accountId: widget.account.id),
      limit: 6,
    );
    return res.valueOrNull?.items ?? const [];
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _instCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final acc = widget.account;
    final canPost =
        widget.profile.permissions.canPostTransaction && !acc.isArchived;

    final (accent, accentBg) = _accountAccent(acc.accountType, cfo, scheme);

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
              Row(
                children: [
                  Expanded(
                    child: EnterpriseModalHeader(
                      title: acc.name,
                      subtitle:
                          '${acc.accountType.label} • ${acc.currencyCode}${acc.institutionLabel != null ? ' • ${acc.institutionLabel}' : ''}',
                      icon: _accountIcon(acc.accountType),
                      iconColor: accent,
                      iconBackgroundColor: accentBg,
                    ),
                  ),
                  if (canPost)
                    IconButton(
                      tooltip: 'Edit account details',
                      onPressed: () => setState(() => _editing = !_editing),
                      icon: Icon(
                        _editing ? Icons.close_rounded : Icons.edit_outlined,
                      ),
                    ),
                ],
              ),

              // Balance Summary Box
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: cfo.surfaceTonal,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  border: Border.all(color: cfo.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            acc.isLiability
                                ? 'CURRENT LIABILITY BALANCE'
                                : 'CURRENT ACCOUNT BALANCE',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: cfo.subtleText,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.7,
                                ),
                          ),
                        ),
                        SyncStatusBadge(status: acc.syncStatus),
                      ],
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: MoneyText(
                        money: acc.balance,
                        masked: widget.masked,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    if (acc.currencyCode !=
                        widget.profile.baseCurrencyCode) ...[
                      const SizedBox(height: 4),
                      MoneyText(
                        money: acc.baseBalance,
                        masked: widget.masked,
                        semanticContextLabel: 'Base value',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: cfo.subtleText),
                      ),
                    ],
                  ],
                ),
              ),

              // Inline Edit Form
              if (_editing) ...[
                const SizedBox(height: AppSpacing.md),
                FintechTextField(
                  label: 'Account Name',
                  controller: _nameCtrl,
                  leadingIcon: Icons.account_balance_wallet_outlined,
                  textCapitalization: TextCapitalization.words,
                  showClearButton: true,
                ),
                const SizedBox(height: AppSpacing.xs),
                FintechTextField(
                  label: 'Institution Label (optional)',
                  controller: _instCtrl,
                  leadingIcon: Icons.business_outlined,
                  textCapitalization: TextCapitalization.words,
                  showClearButton: true,
                ),
                const SizedBox(height: AppSpacing.sm),
                FilledButton.icon(
                  onPressed: _savingEdit
                      ? null
                      : () async {
                          if (_nameCtrl.text.trim().isEmpty) return;
                          setState(() => _savingEdit = true);
                          final nav = Navigator.of(context);
                          await widget.accountRepository.updateAccount(
                            profileId: widget.profile.id,
                            accountId: acc.id,
                            name: _nameCtrl.text.trim(),
                            institutionLabel: _instCtrl.text.trim().isEmpty
                                ? null
                                : _instCtrl.text.trim(),
                          );
                          widget.dashboardBloc.add(
                            const DashboardRefreshRequested(),
                          );
                          if (mounted && nav.canPop()) nav.pop();
                        },
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Save Changes'),
                ),
              ],

              // Quick Posting Actions for this Account
              if (canPost) ...[
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          openAddTransactionSheet(
                            widget.parentContext,
                            widget.profile,
                            initialType: TransactionType.expense,
                            initialSourceAccountId: acc.id,
                          );
                        },
                        icon: const Icon(Icons.north_east_rounded, size: 16),
                        label: const Text('Spend'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          openAddTransactionSheet(
                            widget.parentContext,
                            widget.profile,
                            initialType: TransactionType.income,
                            initialSourceAccountId: acc.id,
                          );
                        },
                        icon: const Icon(Icons.south_west_rounded, size: 16),
                        label: const Text('Receive'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          openAddTransactionSheet(
                            widget.parentContext,
                            widget.profile,
                            initialType: TransactionType.transfer,
                            initialSourceAccountId: acc.id,
                          );
                        },
                        icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                        label: const Text('Transfer'),
                      ),
                    ),
                  ],
                ),
              ],

              // Live Recent Account Statement
              const SizedBox(height: AppSpacing.md),
              SectionHeader(
                title: 'Recent Account Activity',
                trailingLabel: 'Full Ledger',
                onTrailingPressed: () {
                  Navigator.of(context).pop();
                  widget.transactionsBloc.add(
                    TransactionsLoadRequested(
                      filter: TransactionFilter(accountId: acc.id),
                    ),
                  );
                  widget.parentContext.go('/transactions');
                },
              ),
              const SizedBox(height: AppSpacing.xs),
              FutureBuilder<List<TransactionEntity>>(
                future: _recentFuture,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  final items = snap.data ?? const [];
                  if (items.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      child: Text(
                        'No posted transactions for this account yet.',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: cfo.subtleText),
                      ),
                    );
                  }
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      border: Border.all(color: cfo.divider),
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < items.length; i++) ...[
                          if (i > 0) Divider(height: 1, color: cfo.divider),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        items[i].description?.isNotEmpty == true
                                            ? items[i].description!
                                            : (items[i].categoryName ??
                                                  items[i].type.label),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      Text(
                                        UiDateFormatter.shortDayMonth(
                                          items[i].transactionDateUtc,
                                        ),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(color: cfo.subtleText),
                                      ),
                                    ],
                                  ),
                                ),
                                MoneyText(
                                  money: items[i].amount,
                                  masked: widget.masked,
                                  semanticKind: switch (items[i].type) {
                                    TransactionType.income ||
                                    TransactionType.refund => 'income',
                                    TransactionType.expense => 'expense',
                                    TransactionType.transfer => 'transfer',
                                    _ => null,
                                  },
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),

              if (!acc.isArchived) ...[
                const SizedBox(height: AppSpacing.lg),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cfo.expense,
                    side: BorderSide(color: cfo.expense.withValues(alpha: 0.5)),
                  ),
                  onPressed: () async {
                    final confirmed = await showModernConfirmDialog(
                      context: context,
                      title: 'Archive ${acc.name}?',
                      subtitle: 'Historical ledger postings remain intact',
                      icon: Icons.archive_outlined,
                      accent: ModernDialogAccent.warning,
                      confirmLabel: 'Archive',
                      message:
                          'Archived accounts are hidden from active totals and new transactions. You can restore them anytime from Archived accounts.',
                    );
                    if (confirmed != true || !context.mounted) return;
                    final nav = Navigator.of(context);
                    await widget.accountRepository.archiveAccount(
                      profileId: widget.profile.id,
                      accountId: acc.id,
                    );
                    if (context.mounted && nav.canPop()) nav.pop();
                    widget.dashboardBloc.add(const DashboardRefreshRequested());
                  },
                  icon: const Icon(Icons.archive_outlined),
                  label: const Text('Archive Account'),
                ),
              ] else ...[
                const SizedBox(height: AppSpacing.lg),
                FilledButton.tonalIcon(
                  key: const Key('account_restore_btn'),
                  onPressed: () async {
                    final nav = Navigator.of(context);
                    await widget.accountRepository.unarchiveAccount(
                      profileId: widget.profile.id,
                      accountId: acc.id,
                    );
                    if (context.mounted && nav.canPop()) nav.pop();
                    widget.dashboardBloc.add(const DashboardRefreshRequested());
                  },
                  icon: const Icon(Icons.unarchive_outlined),
                  label: const Text('Restore Account'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
