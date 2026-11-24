import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/financial_engine/currency.dart';
import '../../../../core/financial_engine/double_entry_engine.dart';
import '../../../../core/financial_engine/fx_rate.dart';
import '../../../../core/financial_engine/money.dart';
import '../../../../core/utilities/clock.dart';
import '../../../../core/utilities/id_generator.dart';
import '../../../../shared/widgets/enterprise_layout.dart';
import '../../../../shared/widgets/fintech_widgets.dart';
import '../../../../shared/widgets/modern_dialogs.dart';
import '../../../../shared/widgets/modern_dropdown.dart';
import '../../../../shared/widgets/modern_inputs.dart';
import '../../../accounts/domain/entities/financial_account_entity.dart';
import '../../../accounts/domain/repositories/account_repository.dart';
import '../../../accounts/presentation/pages/accounts_page.dart';
import '../../../categories/domain/entities/category_entity.dart';
import '../../../categories/domain/repositories/category_repository.dart';
import '../../../dashboard/presentation/bloc/dashboard_bloc.dart';
import '../../../notifications/data/financial_alerts_coordinator.dart';
import '../../../profiles/domain/entities/profile_entity.dart';
import '../../../profiles/presentation/bloc/active_profile_cubit.dart';
import '../../../settings/presentation/bloc/settings_cubit.dart';
import '../../domain/entities/transaction_entity.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../bloc/transactions_bloc.dart';

/// Covers `SCR-TRAN-001` (Date-Grouped Searchable/Paginated Ledger),
/// `SCR-TRAN-002` (Add Transaction / Multi-Splits / Date Picker / FX),
/// and `SCR-TRAN-003` (Transaction Details, Journal Postings, Linked Refund & Reversals).
class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key});

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  final _searchCtrl = TextEditingController();
  TransactionType? _selectedType;
  bool _onlyDrafts = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _applyFilter({
    TransactionType? type,
    bool onlyDrafts = false,
    bool clearScopedFilters = false,
  }) {
    setState(() {
      _selectedType = type;
      _onlyDrafts = onlyDrafts;
    });
    final existing = context.read<TransactionsBloc>().state.filter;
    context.read<TransactionsBloc>().add(
      TransactionsLoadRequested(
        filter: TransactionFilter(
          searchQuery: _searchCtrl.text,
          type: type,
          status: onlyDrafts ? TransactionStatus.draft : null,
          accountId: clearScopedFilters ? null : existing.accountId,
          categoryId: clearScopedFilters ? null : existing.categoryId,
          fromUtc: clearScopedFilters ? null : existing.fromUtc,
          toUtc: clearScopedFilters ? null : existing.toUtc,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ActiveProfileCubit>().state.activeProfile;
    final hideBalances = context.watch<SettingsCubit>().state.hideBalances;
    final cfo = context.cfoColors;

    if (profile == null) {
      return const EmptyStateView(
        icon: Icons.receipt_long_outlined,
        title: 'No active profile',
        description: 'Select or create a profile to record transactions.',
      );
    }

    return EnterprisePageContainer(
      maxWidth: AppBreakpoints.maxDashboardWidth,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktopTable = constraints.maxWidth >= AppBreakpoints.medium;
          final hPad = constraints.maxWidth >= AppBreakpoints.desktop
              ? AppSpacing.xxl
              : constraints.maxWidth >= AppBreakpoints.tablet
              ? AppSpacing.xl
              : AppSpacing.md;

          final scheme = Theme.of(context).colorScheme;
          final secondaryFilterLabel = _onlyDrafts
              ? 'Drafts'
              : _selectedType == TransactionType.refund
              ? 'Refund'
              : null;

          return Column(
            children: [
              // Ultra-compact zero-waste Search + Sliding Segmented Filter Bar
              Padding(
                padding: EdgeInsets.fromLTRB(hPad, 10, hPad, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: FintechSearchField(
                            controller: _searchCtrl,
                            hintText: 'Search ledger...',
                            height: 42,
                            onChanged: (q) {
                              context.read<TransactionsBloc>().add(
                                TransactionsSearchChanged(q),
                              );
                            },
                            onClear: () {
                              context.read<TransactionsBloc>().add(
                                const TransactionsSearchChanged(''),
                              );
                            },
                          ),
                        ),
                        if (profile.permissions.canPostTransaction) ...[
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 42,
                            child: FilledButton.tonalIcon(
                              key: const Key('ledger_quick_add_btn'),
                              style: FilledButton.styleFrom(
                                backgroundColor: scheme.primaryContainer,
                                foregroundColor: scheme.primary,
                                padding: EdgeInsets.symmetric(
                                  horizontal: isDesktopTable ? 14 : 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusFull,
                                  ),
                                ),
                              ),
                              onPressed: () =>
                                  openAddTransactionSheet(context, profile),
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: Text(
                                isDesktopTable ? 'Add Entry' : 'New',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _LedgerSegmentedFilter(
                            key: const Key('ledger_segmented_filter'),
                            selectedType: _onlyDrafts ? null : _selectedType,
                            hasSecondaryActive: secondaryFilterLabel != null,
                            onSelect: (type) {
                              HapticFeedback.selectionClick();
                              _applyFilter(type: type, onlyDrafts: false);
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        PopupMenuButton<String>(
                          key: const Key('ledger_more_filter_btn'),
                          tooltip: 'More ledger filters',
                          onSelected: (value) {
                            HapticFeedback.selectionClick();
                            if (value == 'refund') {
                              _applyFilter(
                                type: TransactionType.refund,
                                onlyDrafts: false,
                              );
                            } else if (value == 'drafts') {
                              _applyFilter(type: null, onlyDrafts: true);
                            } else {
                              _applyFilter(type: null, onlyDrafts: false);
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'refund',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.replay_rounded,
                                    size: 17,
                                    color:
                                        _selectedType == TransactionType.refund
                                        ? scheme.primary
                                        : cfo.subtleText,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      'Refunds',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight:
                                            _selectedType ==
                                                TransactionType.refund
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'drafts',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.edit_note_rounded,
                                    size: 18,
                                    color: _onlyDrafts
                                        ? scheme.primary
                                        : cfo.subtleText,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      'Drafts',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: _onlyDrafts
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (secondaryFilterLabel != null)
                              const PopupMenuItem(
                                value: 'clear',
                                child: Row(
                                  children: [
                                    Icon(Icons.clear_all_rounded, size: 18),
                                    SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        'Show All',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                          child: Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: secondaryFilterLabel != null
                                  ? scheme.primaryContainer
                                  : cfo.surfaceTonal,
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusFull,
                              ),
                              border: Border.all(
                                color: secondaryFilterLabel != null
                                    ? scheme.primary.withValues(alpha: 0.45)
                                    : cfo.divider,
                              ),
                            ),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Icon(
                                  Icons.tune_rounded,
                                  size: 17,
                                  color: secondaryFilterLabel != null
                                      ? scheme.primary
                                      : cfo.subtleText,
                                ),
                                if (secondaryFilterLabel != null)
                                  Positioned(
                                    right: -3,
                                    top: -3,
                                    child: Container(
                                      width: 7,
                                      height: 7,
                                      decoration: BoxDecoration(
                                        color: scheme.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: BlocBuilder<TransactionsBloc, TransactionsState>(
                  builder: (context, state) {
                    if (state.status == TransactionsStatus.loading &&
                        state.items.isEmpty) {
                      return const DashboardSkeletonView();
                    }
                    if (state.status == TransactionsStatus.failure) {
                      return ErrorStateView(
                        message:
                            state.failure?.message ??
                            'Could not load transactions.',
                        onRetry: () => context.read<TransactionsBloc>().add(
                          const TransactionsLoadRequested(),
                        ),
                      );
                    }
                    if (state.items.isEmpty) {
                      final hasFilter =
                          _selectedType != null ||
                          _onlyDrafts ||
                          _searchCtrl.text.trim().isNotEmpty;
                      return EmptyStateView(
                        icon: hasFilter
                            ? Icons.filter_alt_off_outlined
                            : Icons.receipt_long_outlined,
                        title: hasFilter
                            ? 'No matching entries'
                            : 'No transactions yet',
                        description: hasFilter
                            ? 'No entries match your active search or filter criteria.'
                            : 'Record an expense, income, own-account transfer, or split transaction. Every posted entry creates a balanced double-entry journal.',
                        actionLabel: hasFilter
                            ? 'Reset Filters'
                            : profile.permissions.canPostTransaction
                            ? 'Add Transaction'
                            : null,
                        onAction: hasFilter
                            ? () {
                                _searchCtrl.clear();
                                _applyFilter(type: null, onlyDrafts: false);
                              }
                            : profile.permissions.canPostTransaction
                            ? () => openAddTransactionSheet(context, profile)
                            : null,
                      );
                    }

                    final now = GetIt.I<UtcClock>().nowUtc();
                    final ccy = profile.baseCurrencyCode;
                    var inflowMinor = 0;
                    var outflowMinor = 0;
                    final groups = <_LedgerDayGroup>[];
                    final groupIndexByHeader = <String, int>{};

                    for (final item in state.items) {
                      final hdr = UiDateFormatter.relativeHeader(
                        item.transactionDateUtc,
                        now: now,
                      );
                      final gIdx = groupIndexByHeader.putIfAbsent(hdr, () {
                        groups.add(
                          _LedgerDayGroup(
                            header: hdr,
                            items: [],
                            dayNetMinor: 0,
                          ),
                        );
                        return groups.length - 1;
                      });
                      final group = groups[gIdx];
                      group.items.add(item);

                      if (item.isReversed ||
                          item.status == TransactionStatus.draft) {
                        continue;
                      }
                      if (item.type == TransactionType.income ||
                          item.type == TransactionType.refund) {
                        inflowMinor += item.baseAmount.amountMinor;
                        group.dayNetMinor += item.baseAmount.amountMinor;
                      } else if (item.type == TransactionType.expense) {
                        outflowMinor += item.baseAmount.amountMinor;
                        group.dayNetMinor -= item.baseAmount.amountMinor;
                      }
                    }

                    final activeFilter = state.filter;
                    final hasScopedFilter =
                        activeFilter.accountId != null ||
                        activeFilter.categoryId != null ||
                        activeFilter.fromUtc != null ||
                        activeFilter.toUtc != null;

                    return RefreshIndicator(
                      onRefresh: () async {
                        context.read<TransactionsBloc>().add(
                          TransactionsLoadRequested(
                            filter: TransactionFilter(
                              searchQuery: _searchCtrl.text,
                              type: _selectedType,
                              status: _onlyDrafts
                                  ? TransactionStatus.draft
                                  : null,
                              accountId: activeFilter.accountId,
                              categoryId: activeFilter.categoryId,
                              fromUtc: activeFilter.fromUtc,
                              toUtc: activeFilter.toUtc,
                            ),
                          ),
                        );
                      },
                      child: CustomScrollView(
                        scrollCacheExtent: const ScrollCacheExtent.pixels(640),
                        slivers: [
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 8),
                            sliver: SliverToBoxAdapter(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _LedgerPulseStrip(
                                    totalCount: state.totalCount,
                                    inflow: Money(
                                      amountMinor: inflowMinor,
                                      currencyCode: ccy,
                                    ),
                                    outflow: Money(
                                      amountMinor: outflowMinor,
                                      currencyCode: ccy,
                                    ),
                                    net: Money(
                                      amountMinor: inflowMinor - outflowMinor,
                                      currencyCode: ccy,
                                    ),
                                    masked: hideBalances,
                                  ),
                                  if (secondaryFilterLabel != null ||
                                      hasScopedFilter) ...[
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        if (secondaryFilterLabel != null)
                                          InputChip(
                                            visualDensity:
                                                VisualDensity.compact,
                                            label: Text(
                                              'Filter: $secondaryFilterLabel',
                                            ),
                                            onDeleted: () => _applyFilter(
                                              type: null,
                                              onlyDrafts: false,
                                            ),
                                          ),
                                        if (hasScopedFilter)
                                          InputChip(
                                            key: const Key(
                                              'ledger_scoped_filter_chip',
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                            label: Text(
                                              activeFilter.accountId != null
                                                  ? 'Account Filter'
                                                  : activeFilter.categoryId !=
                                                        null
                                                  ? 'Category Filter'
                                                  : 'Date Filter',
                                            ),
                                            onDeleted: () => _applyFilter(
                                              type: _selectedType,
                                              onlyDrafts: _onlyDrafts,
                                              clearScopedFilters: true,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          if (isDesktopTable)
                            SliverPadding(
                              padding: EdgeInsets.fromLTRB(
                                hPad + AppSpacing.md,
                                2,
                                hPad + AppSpacing.md,
                                4,
                              ),
                              sliver: SliverToBoxAdapter(
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 4,
                                      child: Text(
                                        'TRANSACTION',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: cfo.subtleText,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.7,
                                            ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        'CATEGORY',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: cfo.subtleText,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.7,
                                            ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        'STATUS',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: cfo.subtleText,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.7,
                                            ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 140,
                                      child: Text(
                                        'AMOUNT',
                                        textAlign: TextAlign.right,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: cfo.subtleText,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.7,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 32),
                            sliver: SliverList.builder(
                              itemCount:
                                  groups.length + (state.hasMore ? 1 : 0),
                              itemBuilder: (context, gIdx) {
                                if (gIdx >= groups.length) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: AppSpacing.md,
                                    ),
                                    child: Center(
                                      child: OutlinedButton(
                                        onPressed: state.isLoadingMore
                                            ? null
                                            : () => context
                                                  .read<TransactionsBloc>()
                                                  .add(
                                                    const TransactionsLoadMoreRequested(),
                                                  ),
                                        child: state.isLoadingMore
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : Text(
                                                'Load more (${state.items.length} of ${state.totalCount})',
                                              ),
                                      ),
                                    ),
                                  );
                                }

                                final group = groups[gIdx];
                                return Padding(
                                  padding: EdgeInsets.only(
                                    top: gIdx == 0 ? 2 : 12,
                                  ),
                                  child: _GroupedDayLedgerCard(
                                    group: group,
                                    currencyCode: ccy,
                                    isDesktopTable: isDesktopTable,
                                    hideBalances: hideBalances,
                                    onTapTx: (txId) => _openTransactionDetail(
                                      context,
                                      profile,
                                      txId,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openTransactionDetail(
    BuildContext context,
    FinancialProfile profile,
    String txId,
  ) async {
    final repo = GetIt.I<TransactionRepository>();
    final res = await repo.getTransactionDetail(profile.id, txId);
    if (!context.mounted || res.isFailure) return;
    final tx = res.valueOrNull!;
    final cfo = context.cfoColors;

    await showEnterpriseModal<void>(
      context: context,
      maxWidth: 560,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _TransactionAvatar(type: tx.type),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tx.type.label,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            UiDateFormatter.shortDayMonthYear(
                              tx.transactionDateUtc,
                            ),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: cfo.subtleText),
                          ),
                        ],
                      ),
                    ),
                    SyncStatusBadge(status: tx.syncStatus),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(sheetCtx).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: cfo.surfaceTonal,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MoneyText(
                        money: tx.amount,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      if (tx.amount.currencyCode !=
                          tx.baseAmount.currencyCode) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Base value: ${tx.baseAmount.format()} (FX source: ${tx.fxRateSource})',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: cfo.subtleText),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _DetailRow(
                  label: 'Status',
                  value:
                      '${tx.status.label}${tx.isReversed ? ' (Reversed)' : ''}',
                ),
                if (tx.sourceAccountName != null)
                  _DetailRow(label: 'Source', value: tx.sourceAccountName!),
                if (tx.destinationAccountName != null)
                  _DetailRow(
                    label: 'Destination',
                    value: tx.destinationAccountName!,
                  ),
                if (tx.categoryName != null)
                  _DetailRow(label: 'Category', value: tx.categoryName!),
                if (tx.description != null && tx.description!.isNotEmpty)
                  _DetailRow(label: 'Note', value: tx.description!),
                if (tx.splits.isNotEmpty) ...[
                  const Divider(height: 24),
                  Text(
                    'Splits (${tx.splits.length})',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  for (final s in tx.splits)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(child: Text(s.categoryName)),
                          Text(
                            Money(
                              amountMinor: s.amountMinor,
                              currencyCode: tx.amount.currencyCode,
                            ).format(),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                ],
                if (tx.postings.isNotEmpty) ...[
                  const Divider(height: 24),
                  Text(
                    'Double-Entry Ledger Postings (${tx.baseAmount.currencyCode})',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: cfo.surfaceTonal,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: Column(
                      children: [
                        for (final p in tx.postings)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    p.ledgerAccountName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: p.side == PostingSide.debit
                                        ? cfo.expenseContainer
                                        : cfo.incomeContainer,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    p.side == PostingSide.debit ? 'DR' : 'CR',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: p.side == PostingSide.debit
                                          ? cfo.expense
                                          : cfo.income,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Text(
                                  Money(
                                    amountMinor: p.baseAmountMinor,
                                    currencyCode: tx.baseAmount.currencyCode,
                                  ).format(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                if (tx.status == TransactionStatus.draft)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final confirmed = await showModernConfirmDialog(
                              context: sheetCtx,
                              title: 'Delete Draft?',
                              subtitle: 'Unposted entry will be removed',
                              icon: Icons.delete_outline_rounded,
                              accent: ModernDialogAccent.danger,
                              confirmLabel: 'Delete Draft',
                              message:
                                  'This draft has not been posted to your ledger. Deleting it cannot be undone.',
                            );
                            if (confirmed != true) return;
                            await repo.deleteDraftTransaction(
                              profile.id,
                              tx.id,
                            );
                            if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                            if (context.mounted) {
                              showFintechToast(
                                context,
                                'Draft deleted.',
                                tone: FintechToastTone.info,
                              );
                              _refreshAll(context);
                            }
                          },
                          child: const Text('Delete Draft'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: FilledButton(
                          onPressed: () async {
                            final r = await repo.postDraftTransaction(
                              profile.id,
                              tx.id,
                            );
                            if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                            if (context.mounted) {
                              if (r.isFailure) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(r.failureOrNull!.message),
                                  ),
                                );
                              } else {
                                await GetIt.I<FinancialAlertsCoordinator>()
                                    .evaluateAfterTransaction(profile.id);
                              }
                              if (context.mounted) _refreshAll(context);
                            }
                          },
                          child: const Text('Post Now'),
                        ),
                      ),
                    ],
                  )
                else if (tx.status == TransactionStatus.posted &&
                    !tx.isReversed) ...[
                  if (tx.type == TransactionType.expense &&
                      tx.sourceAccountId != null &&
                      tx.categoryId != null &&
                      profile.permissions.canPostTransaction) ...[
                    FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.of(sheetCtx).pop();
                        openAddTransactionSheet(
                          context,
                          profile,
                          initialType: TransactionType.refund,
                          initialRelatedTransactionId: tx.id,
                          initialDestinationAccountId: tx.sourceAccountId,
                          initialCategoryId: tx.categoryId,
                          initialAmountMinor: tx.amount.amountMinor,
                          initialCurrencyCode: tx.amount.currencyCode,
                          initialDescription:
                              'Refund: ${tx.description?.isNotEmpty == true ? tx.description : (tx.categoryName ?? "Expense")}',
                        );
                      },
                      icon: const Icon(Icons.replay_rounded),
                      label: const Text('Record Linked Refund'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  if (profile.permissions.canReverseOrVoid)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cfo.expense,
                        side: BorderSide(
                          color: cfo.expense.withValues(alpha: 0.45),
                        ),
                      ),
                      onPressed: () async {
                        final reasonCtrl = TextEditingController(
                          text: 'User correction reversal',
                        );
                        final reason = await showModernDialog<String>(
                          context: sheetCtx,
                          builder: (dlgCtx) => ModernDialogShell(
                            title: 'Reverse Posted Entry?',
                            subtitle:
                                'Posts an immutable compensating journal entry',
                            icon: Icons.undo_rounded,
                            accent: ModernDialogAccent.danger,
                            confirmLabel: 'Post Reversal',
                            onConfirm: () => Navigator.of(dlgCtx).pop(
                              reasonCtrl.text.trim().isEmpty
                                  ? 'User correction reversal'
                                  : reasonCtrl.text.trim(),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'The original transaction remains in the audit trail and a counter-entry restores affected balances.',
                                  style: Theme.of(dlgCtx).textTheme.bodySmall
                                      ?.copyWith(
                                        color: dlgCtx.cfoColors.subtleText,
                                      ),
                                ),
                                const SizedBox(height: 12),
                                FintechTextField(
                                  label: 'Reversal Reason',
                                  controller: reasonCtrl,
                                  leadingIcon: Icons.notes_rounded,
                                ),
                              ],
                            ),
                          ),
                        );
                        reasonCtrl.dispose();
                        if (reason == null) return;
                        final rev = await repo.reversePostedTransaction(
                          profile.id,
                          originalTransactionId: tx.id,
                          reason: reason,
                        );
                        if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                        if (context.mounted) {
                          showFintechToast(
                            context,
                            rev.isSuccess
                                ? 'Compensating reversal journal posted.'
                                : rev.failureOrNull!.message,
                            tone: rev.isSuccess
                                ? FintechToastTone.success
                                : FintechToastTone.danger,
                          );
                          _refreshAll(context);
                        }
                      },
                      icon: const Icon(Icons.undo_rounded),
                      label: const Text(
                        'Reverse Posted Entry (Immutable Correction)',
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _refreshAll(BuildContext context) {
    context.read<TransactionsBloc>().add(const TransactionsLoadRequested());
    context.read<DashboardBloc>().add(const DashboardRefreshRequested());
  }
}

class _SplitLineDraft {
  _SplitLineDraft({required this.categoryId, String initialAmount = ''})
    : amountCtrl = TextEditingController(text: initialAmount);

  String categoryId;
  final TextEditingController amountCtrl;

  void dispose() => amountCtrl.dispose();
}

/// Reusable `SCR-TRAN-002` modal sheet for recording Income, Expense (with optional Multi-Splits),
/// Transfer (same or cross-currency with 1-tap swap), Date selection, and Linked Refunds.
Future<void> openAddTransactionSheet(
  BuildContext context,
  FinancialProfile profile, {
  TransactionType initialType = TransactionType.expense,
  String? initialRelatedTransactionId,
  String? initialSourceAccountId,
  String? initialDestinationAccountId,
  String? initialCategoryId,
  int? initialAmountMinor,
  String? initialCurrencyCode,
  String? initialDescription,
}) async {
  final accountsRes = await GetIt.I<AccountRepository>().listAccounts(
    profile.id,
  );
  final categoriesRes = await GetIt.I<CategoryRepository>().listCategories(
    profile.id,
  );
  if (!context.mounted) return;

  final accounts = accountsRes.valueOrNull ?? const <FinancialAccountEntity>[];
  final categories = categoriesRes.valueOrNull ?? const <CategoryEntity>[];

  if (accounts.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Add your first account first to record transactions.',
        ),
        action: SnackBarAction(
          label: 'Add Account',
          onPressed: () => openAddAccountModal(context, profile),
        ),
      ),
    );
    return;
  }

  await showEnterpriseModal<void>(
    context: context,
    maxWidth: 580,
    builder: (sheetCtx) => _AddTransactionSheetBody(
      profile: profile,
      accounts: accounts,
      categories: categories,
      initialType: initialType,
      initialRelatedTransactionId: initialRelatedTransactionId,
      initialSourceAccountId: initialSourceAccountId,
      initialDestinationAccountId: initialDestinationAccountId,
      initialCategoryId: initialCategoryId,
      initialAmountMinor: initialAmountMinor,
      initialCurrencyCode: initialCurrencyCode,
      initialDescription: initialDescription,
    ),
  );
}

class _AddTransactionSheetBody extends StatefulWidget {
  const _AddTransactionSheetBody({
    required this.profile,
    required this.accounts,
    required this.categories,
    required this.initialType,
    this.initialRelatedTransactionId,
    this.initialSourceAccountId,
    this.initialDestinationAccountId,
    this.initialCategoryId,
    this.initialAmountMinor,
    this.initialCurrencyCode,
    this.initialDescription,
  });

  final FinancialProfile profile;
  final List<FinancialAccountEntity> accounts;
  final List<CategoryEntity> categories;
  final TransactionType initialType;
  final String? initialRelatedTransactionId;
  final String? initialSourceAccountId;
  final String? initialDestinationAccountId;
  final String? initialCategoryId;
  final int? initialAmountMinor;
  final String? initialCurrencyCode;
  final String? initialDescription;

  @override
  State<_AddTransactionSheetBody> createState() =>
      _AddTransactionSheetBodyState();
}

class _AddTransactionSheetBodyState extends State<_AddTransactionSheetBody> {
  late final TextEditingController _amountCtrl;
  final TextEditingController _destAmountCtrl = TextEditingController();
  final TextEditingController _fxCtrl = TextEditingController();
  late final TextEditingController _noteCtrl;
  late final String _idempotencyKey;

  late TransactionType _txType;
  bool _saveAsDraft = false;
  late String _sourceAccountId;
  late String _destAccountId;
  late final List<CategoryEntity> _expenseCats;
  String? _categoryId;
  late String _currencyCode;
  late DateTime _txDate;
  bool _isSubmitting = false;
  bool _useSplits = false;
  final List<_SplitLineDraft> _splitRows = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final accounts = widget.accounts;
    final initCurr = widget.initialCurrencyCode ?? accounts.first.currencyCode;
    final initSpec = CurrencyCatalog.requireByCode(initCurr);
    final initAmountStr = widget.initialAmountMinor != null
        ? (widget.initialAmountMinor! / initSpec.minorFactor).toStringAsFixed(
            initSpec.minorUnit,
          )
        : '';

    _amountCtrl = TextEditingController(text: initAmountStr);
    _noteCtrl = TextEditingController(text: widget.initialDescription ?? '');
    _idempotencyKey = GetIt.I<IdGenerator>().nextUuid();
    _txType = widget.initialType;
    _sourceAccountId = widget.initialSourceAccountId ?? accounts.first.id;
    _destAccountId =
        widget.initialDestinationAccountId ??
        (accounts.length > 1 ? accounts[1].id : accounts.first.id);
    _expenseCats = widget.categories
        .where((c) => c.categoryType == CategoryType.expense)
        .toList();
    _categoryId = widget.initialCategoryId ?? _expenseCats.firstOrNull?.id;
    _currencyCode = initCurr;
    _txDate = GetIt.I<UtcClock>().nowUtc();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _destAmountCtrl.dispose();
    _fxCtrl.dispose();
    _noteCtrl.dispose();
    for (final s in _splitRows) {
      s.dispose();
    }
    super.dispose();
  }

  void _ensureInitialSplitRows() {
    if (_splitRows.isEmpty && _expenseCats.isNotEmpty) {
      _splitRows.add(_SplitLineDraft(categoryId: _expenseCats.first.id));
      _splitRows.add(
        _SplitLineDraft(
          categoryId: _expenseCats.length > 1
              ? _expenseCats[1].id
              : _expenseCats.first.id,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final accounts = widget.accounts;

    final filteredCats = widget.categories.where((c) {
      if (_txType == TransactionType.income) {
        return c.categoryType == CategoryType.income;
      }
      return c.categoryType == CategoryType.expense;
    }).toList();

    if (_categoryId != null && !filteredCats.any((c) => c.id == _categoryId)) {
      _categoryId = filteredCats.firstOrNull?.id;
    }

    final needsFx = _currencyCode != profile.baseCurrencyCode;
    final destAcc = accounts.where((a) => a.id == _destAccountId).firstOrNull;
    final isCrossCurrencyTransfer =
        _txType == TransactionType.transfer &&
        destAcc != null &&
        destAcc.currencyCode != _currencyCode;
    final currSpec = CurrencyCatalog.requireByCode(_currencyCode);

    final totalParsedMinor = Money.parseDecimal(
      _amountCtrl.text.trim().isEmpty ? '0' : _amountCtrl.text,
      currency: currSpec,
      allowZero: true,
    ).valueOrNull?.amountMinor;

    final allocatedMinor = _splitRows.fold<int>(0, (sum, row) {
      final p = Money.parseDecimal(
        row.amountCtrl.text.trim().isEmpty ? '0' : row.amountCtrl.text,
        currency: currSpec,
        allowZero: true,
      );
      return sum + (p.valueOrNull?.amountMinor ?? 0);
    });
    final remainingMinor = (totalParsedMinor ?? 0) - allocatedMinor;

    void addQuickAmount(int majorDelta) {
      final current =
          Money.parseDecimal(
            _amountCtrl.text.trim().isEmpty ? '0' : _amountCtrl.text,
            currency: currSpec,
            allowZero: true,
          ).valueOrNull?.amountMinor ??
          0;
      final nextMinor = current + (majorDelta * currSpec.minorFactor);
      final val = nextMinor / currSpec.minorFactor;
      setState(() {
        _amountCtrl.text = currSpec.minorUnit == 0
            ? val.round().toString()
            : val.toStringAsFixed(currSpec.minorUnit);
      });
    }

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
                title: widget.initialRelatedTransactionId != null
                    ? 'Record Linked Refund'
                    : 'New Transaction',
                subtitle: 'Double-entry posted voucher',
                icon: Icons.receipt_long_rounded,
              ),
              Builder(
                builder: (context) {
                  final cfo = context.cfoColors;
                  final scheme = Theme.of(context).colorScheme;
                  final animDur = AppMotion.resolve(context, AppMotion.fast);
                  const txTypes = [
                    (TransactionType.expense, 'Expense'),
                    (TransactionType.income, 'Income'),
                    (TransactionType.transfer, 'Transfer'),
                    (TransactionType.refund, 'Refund'),
                  ];
                  return Container(
                    height: 40,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: cfo.surfaceTonal,
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusFull,
                      ),
                      border: Border.all(
                        color: cfo.divider.withValues(alpha: 0.75),
                      ),
                    ),
                    child: Row(
                      children: [
                        for (final item in txTypes)
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _txType = item.$1;
                                  if (_txType != TransactionType.expense) {
                                    _useSplits = false;
                                  }
                                  _errorMessage = null;
                                });
                              },
                              child: AnimatedContainer(
                                duration: animDur,
                                curve: Curves.easeOutCubic,
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _txType == item.$1
                                      ? cfo.surfaceElevated
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusFull,
                                  ),
                                  boxShadow: _txType == item.$1
                                      ? [
                                          BoxShadow(
                                            color: cfo.cardShadow,
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    item.$2,
                                    maxLines: 1,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: _txType == item.$1
                                              ? switch (item.$1) {
                                                  TransactionType.expense =>
                                                    cfo.expense,
                                                  TransactionType.income =>
                                                    cfo.income,
                                                  TransactionType.transfer =>
                                                    cfo.transfer,
                                                  _ => scheme.primary,
                                                }
                                              : cfo.subtleText,
                                          fontWeight: _txType == item.$1
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                        ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: context.cfoColors.expenseContainer,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: context.cfoColors.expense),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: FintechTextField(
                      label: 'Amount ($_currencyCode)',
                      hintText: '0.00',
                      controller: _amountCtrl,
                      onChanged: (_) => setState(() {}),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      tabularFigures: true,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FintechDropdownField<String>(
                      key: const Key('tx_currency_dropdown'),
                      label: 'Currency',
                      value: _currencyCode,
                      compact: true,
                      searchable: true,
                      searchHint: 'Search currency...',
                      minMenuWidth: 260,
                      options: FintechDropdownOption.builtInCurrencies(
                        compactSelected: true,
                      ),
                      onChanged: (v) => setState(() => _currencyCode = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final inc in const [100, 500, 1000, 5000]) ...[
                      ActionChip(
                        label: Text('+$inc'),
                        onPressed: () => addQuickAmount(inc),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              InkWell(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _txDate.toLocal(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null && mounted) {
                    setState(() {
                      _txDate = DateTime.utc(
                        picked.year,
                        picked.month,
                        picked.day,
                        _txDate.hour,
                        _txDate.minute,
                        _txDate.second,
                      );
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: context.cfoColors.surfaceTonal,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, size: 18),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Date: ${UiDateFormatter.shortDayMonthYear(_txDate.toIso8601String())}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      Text(
                        'Change',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              if (needsFx) ...[
                const SizedBox(height: AppSpacing.sm),
                FintechTextField(
                  label:
                      'FX Rate (1 $_currencyCode = ? ${profile.baseCurrencyCode})',
                  helperText:
                      'Required for posting non-base currency (or toggle Save as Draft).',
                  controller: _fxCtrl,
                  leadingIcon: Icons.currency_exchange_rounded,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              if (_txType == TransactionType.expense ||
                  _txType == TransactionType.transfer)
                FintechDropdownField<String>(
                  key: const Key('tx_source_account_dropdown'),
                  label: 'Source Account',
                  value: _sourceAccountId,
                  leadingIcon: Icons.account_balance_wallet_outlined,
                  options: accounts
                      .map(
                        (a) => FintechDropdownOption<String>(
                          value: a.id,
                          label: a.name,
                          selectedLabel: '${a.name} (${a.currencyCode})',
                          subtitle: a.accountType.label,
                          badge: a.currencyCode,
                          icon: a.accountType.isLiability
                              ? Icons.credit_card_rounded
                              : Icons.account_balance_rounded,
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    final chosen = accounts.firstWhere((a) => a.id == v);
                    setState(() {
                      _sourceAccountId = v;
                      _currencyCode = chosen.currencyCode;
                    });
                  },
                ),
              if (_txType == TransactionType.transfer && accounts.length >= 2)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() {
                        final oldSrc = _sourceAccountId;
                        _sourceAccountId = _destAccountId;
                        _destAccountId = oldSrc;
                        final newSrc = accounts.firstWhere(
                          (a) => a.id == _sourceAccountId,
                        );
                        _currencyCode = newSrc.currencyCode;
                      });
                    },
                    icon: const Icon(Icons.swap_vert_rounded, size: 18),
                    label: const Text('Swap accounts'),
                  ),
                ),
              if (_txType == TransactionType.income ||
                  _txType == TransactionType.transfer ||
                  _txType == TransactionType.refund) ...[
                if (_txType == TransactionType.transfer)
                  const SizedBox(height: AppSpacing.xxs),
                FintechDropdownField<String>(
                  key: const Key('tx_dest_account_dropdown'),
                  label: 'Destination Account',
                  value: _destAccountId,
                  leadingIcon: Icons.savings_outlined,
                  options: accounts
                      .map(
                        (a) => FintechDropdownOption<String>(
                          value: a.id,
                          label: a.name,
                          selectedLabel: '${a.name} (${a.currencyCode})',
                          subtitle: a.accountType.label,
                          badge: a.currencyCode,
                          icon: a.accountType.isLiability
                              ? Icons.credit_card_rounded
                              : Icons.account_balance_rounded,
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _destAccountId = v),
                ),
              ],
              if (isCrossCurrencyTransfer) ...[
                const SizedBox(height: AppSpacing.sm),
                FintechTextField(
                  label: 'Destination Amount (${destAcc.currencyCode})',
                  hintText: '0.00',
                  controller: _destAmountCtrl,
                  leadingIcon: Icons.payments_outlined,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ],
              if (_txType == TransactionType.expense &&
                  _expenseCats.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                FintechSwitchCard(
                  title: 'Split across multiple categories',
                  subtitle: 'Allocate this expense into itemized lines',
                  value: _useSplits,
                  onChanged: (v) {
                    setState(() {
                      _useSplits = v;
                      if (v) _ensureInitialSplitRows();
                    });
                  },
                ),
              ],
              if (_txType != TransactionType.transfer && !_useSplits) ...[
                const SizedBox(height: AppSpacing.xs),
                FintechDropdownField<String>(
                  key: const Key('tx_category_dropdown'),
                  label: 'Category',
                  value: _categoryId,
                  leadingIcon: Icons.category_outlined,
                  searchable: filteredCats.length >= 6,
                  searchHint: 'Search categories...',
                  options: filteredCats
                      .map(
                        (c) => FintechDropdownOption<String>(
                          value: c.id,
                          label: c.name,
                          icon: c.categoryType == CategoryType.income
                              ? Icons.arrow_downward_rounded
                              : Icons.local_offer_outlined,
                          iconColor: c.categoryType == CategoryType.income
                              ? context.cfoColors.income
                              : context.cfoColors.expense,
                          iconBackground: c.categoryType == CategoryType.income
                              ? context.cfoColors.incomeContainer
                              : context.cfoColors.expenseContainer,
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _categoryId = v),
                ),
              ],
              if (_useSplits && _txType == TransactionType.expense) ...[
                const SizedBox(height: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: context.cfoColors.surfaceTonal,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpacing.sm,
                        runSpacing: 4,
                        children: [
                          Text(
                            'Split Lines (${_splitRows.length})',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          Text(
                            'Remaining: ${Money(amountMinor: remainingMinor, currencyCode: _currencyCode).format()}',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: remainingMinor == 0
                                      ? context.cfoColors.success
                                      : context.cfoColors.warning,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      for (var i = 0; i < _splitRows.length; i++) ...[
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: FintechDropdownField<String>(
                                label: 'Category',
                                value: _splitRows[i].categoryId,
                                compact: true,
                                searchable: _expenseCats.length >= 6,
                                searchHint: 'Search categories...',
                                minMenuWidth: 230,
                                options: _expenseCats
                                    .map(
                                      (c) => FintechDropdownOption<String>(
                                        value: c.id,
                                        label: c.name,
                                        icon: Icons.local_offer_outlined,
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) => setState(
                                  () => _splitRows[i].categoryId = v,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              flex: 2,
                              child: FintechTextField(
                                label: 'Amt ($_currencyCode)',
                                hintText: '0.00',
                                controller: _splitRows[i].amountCtrl,
                                compact: true,
                                onChanged: (_) => setState(() {}),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                              ),
                            ),
                            if (_splitRows.length > 2)
                              IconButton(
                                tooltip: 'Remove split line',
                                onPressed: () {
                                  setState(() {
                                    final removed = _splitRows.removeAt(i);
                                    WidgetsBinding.instance
                                        .addPostFrameCallback(
                                          (_) => removed.dispose(),
                                        );
                                  });
                                },
                                icon: const Icon(Icons.delete_outline),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                      ],
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _splitRows.add(
                              _SplitLineDraft(
                                categoryId: _expenseCats.first.id,
                              ),
                            );
                          });
                        },
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add Split Line'),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              FintechTextField(
                label: 'Description / Note (optional)',
                hintText: 'Add a memo or merchant name',
                controller: _noteCtrl,
                leadingIcon: Icons.notes_rounded,
                showClearButton: true,
              ),
              const SizedBox(height: AppSpacing.xs),
              FintechSwitchCard(
                title: 'Save as Draft',
                subtitle: 'Keep unposted until you confirm it later',
                value: _saveAsDraft,
                onChanged: (v) => setState(() => _saveAsDraft = v),
              ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton(
                onPressed: _isSubmitting
                    ? null
                    : () async {
                        final parsedAmt = Money.parseDecimal(
                          _amountCtrl.text,
                          currency: currSpec,
                        );
                        if (parsedAmt.isFailure) {
                          setState(
                            () => _errorMessage =
                                parsedAmt.failureOrNull!.message,
                          );
                          return;
                        }

                        final builtSplits = <SplitCommandLine>[];
                        if (_useSplits && _txType == TransactionType.expense) {
                          if (_splitRows.length < 2) {
                            setState(
                              () => _errorMessage =
                                  'Split expense requires at least 2 category lines.',
                            );
                            return;
                          }
                          var sumMinor = 0;
                          for (final row in _splitRows) {
                            final lineParsed = Money.parseDecimal(
                              row.amountCtrl.text,
                              currency: currSpec,
                            );
                            if (lineParsed.isFailure) {
                              setState(
                                () => _errorMessage =
                                    'Every split line needs a positive amount.',
                              );
                              return;
                            }
                            final lineMinor =
                                lineParsed.valueOrNull!.amountMinor;
                            sumMinor += lineMinor;
                            builtSplits.add(
                              SplitCommandLine(
                                categoryId: row.categoryId,
                                amountMinor: lineMinor,
                              ),
                            );
                          }
                          if (sumMinor != parsedAmt.valueOrNull!.amountMinor) {
                            setState(
                              () => _errorMessage =
                                  'Split lines total must match the transaction amount.',
                            );
                            return;
                          }
                        }

                        int? dstAmtMinor;
                        if (isCrossCurrencyTransfer) {
                          final dstSpec = CurrencyCatalog.requireByCode(
                            destAcc.currencyCode,
                          );
                          final parsedDst = Money.parseDecimal(
                            _destAmountCtrl.text,
                            currency: dstSpec,
                          );
                          if (parsedDst.isFailure) {
                            setState(
                              () => _errorMessage =
                                  parsedDst.failureOrNull!.message,
                            );
                            return;
                          }
                          dstAmtMinor = parsedDst.valueOrNull!.amountMinor;
                        }

                        FxRate? fxRate;
                        if (needsFx && _fxCtrl.text.trim().isNotEmpty) {
                          final parsedFx = FxRate.parseDecimalRate(
                            rawRate: _fxCtrl.text,
                            fromCurrencyCode: _currencyCode,
                            toCurrencyCode: profile.baseCurrencyCode,
                            source: 'manual',
                            effectiveAtUtc: _txDate.toIso8601String(),
                          );
                          if (parsedFx.isFailure) {
                            setState(
                              () => _errorMessage =
                                  parsedFx.failureOrNull!.message,
                            );
                            return;
                          }
                          fxRate = parsedFx.valueOrNull;
                        }

                        setState(() {
                          _isSubmitting = true;
                          _errorMessage = null;
                        });

                        final txBloc = context.read<TransactionsBloc>();
                        final dashBloc = context.read<DashboardBloc>();
                        final nav = Navigator.of(context);

                        final res = await GetIt.I<TransactionRepository>()
                            .createTransaction(
                              profile.id,
                              CreateTransactionCommand(
                                idempotencyKey: _idempotencyKey,
                                type: _txType,
                                amountMinor: parsedAmt.valueOrNull!.amountMinor,
                                currencyCode: _currencyCode,
                                destinationAmountMinor: dstAmtMinor,
                                destinationCurrencyCode: isCrossCurrencyTransfer
                                    ? destAcc.currencyCode
                                    : null,
                                transactionDateUtc: _txDate.toIso8601String(),
                                sourceAccountId:
                                    (_txType == TransactionType.expense ||
                                        _txType == TransactionType.transfer)
                                    ? _sourceAccountId
                                    : null,
                                destinationAccountId:
                                    (_txType == TransactionType.income ||
                                        _txType == TransactionType.transfer ||
                                        _txType == TransactionType.refund)
                                    ? _destAccountId
                                    : null,
                                categoryId:
                                    (_txType == TransactionType.transfer ||
                                        _useSplits)
                                    ? null
                                    : _categoryId,
                                relatedTransactionId:
                                    _txType == TransactionType.refund
                                    ? widget.initialRelatedTransactionId
                                    : null,
                                splits: builtSplits,
                                description: _noteCtrl.text,
                                fxRate: fxRate,
                                saveAsDraft: _saveAsDraft,
                              ),
                            );

                        if (!mounted) return;
                        if (res.isFailure) {
                          setState(() {
                            _isSubmitting = false;
                            _errorMessage = res.failureOrNull!.message;
                          });
                          return;
                        }

                        txBloc.add(const TransactionsLoadRequested());
                        dashBloc.add(const DashboardRefreshRequested());
                        if (!_saveAsDraft) {
                          await GetIt.I<FinancialAlertsCoordinator>()
                              .evaluateAfterTransaction(profile.id);
                        }
                        if (!mounted) return;
                        nav.pop();
                      },
                child: Text(_saveAsDraft ? 'Save Draft' : 'Post Transaction'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransactionAvatar extends StatelessWidget {
  const _TransactionAvatar({required this.type, this.size = 38});
  final TransactionType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final (IconData icon, Color fg, Color bg) = switch (type) {
      TransactionType.income => (
        Icons.south_west_rounded,
        cfo.income,
        cfo.incomeContainer,
      ),
      TransactionType.refund => (
        Icons.replay_rounded,
        cfo.income,
        cfo.incomeContainer,
      ),
      TransactionType.expense => (
        Icons.north_east_rounded,
        cfo.expense,
        cfo.expenseContainer,
      ),
      TransactionType.transfer => (
        Icons.swap_horiz_rounded,
        cfo.transfer,
        cfo.transferContainer,
      ),
      TransactionType.openingBalance || TransactionType.adjustment => (
        Icons.tune_rounded,
        cfo.warning,
        cfo.warningContainer,
      ),
    };
    return IconSquircle(
      icon: icon,
      iconColor: fg,
      backgroundColor: bg,
      size: size,
    );
  }
}

class _StatusTagChip extends StatelessWidget {
  const _StatusTagChip({
    required this.label,
    required this.fg,
    required this.bg,
  });

  final String label;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.cfoColors.subtleText,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerSegmentedFilter extends StatelessWidget {
  const _LedgerSegmentedFilter({
    required this.selectedType,
    required this.hasSecondaryActive,
    required this.onSelect,
    super.key,
  });

  final TransactionType? selectedType;
  final bool hasSecondaryActive;
  final ValueChanged<TransactionType?> onSelect;

  static const _segments = <(TransactionType?, String)>[
    (null, 'All'),
    (TransactionType.expense, 'Expense'),
    (TransactionType.income, 'Income'),
    (TransactionType.transfer, 'Transfer'),
  ];

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final duration = AppMotion.resolve(context, AppMotion.fast);

    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: cfo.surfaceTonal,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(color: cfo.divider),
      ),
      child: Row(
        children: [
          for (final seg in _segments)
            Expanded(
              child: Builder(
                builder: (context) {
                  final active = !hasSecondaryActive && selectedType == seg.$1;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelect(seg.$1),
                    child: AnimatedContainer(
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active
                            ? cfo.surfaceElevated
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusFull,
                        ),
                        boxShadow: active
                            ? [
                                BoxShadow(
                                  color: cfo.cardShadow,
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            seg.$2,
                            maxLines: 1,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: active
                                      ? scheme.primary
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
    );
  }
}

class _LedgerDayGroup {
  _LedgerDayGroup({
    required this.header,
    required this.items,
    required this.dayNetMinor,
  });

  final String header;
  final List<TransactionEntity> items;
  int dayNetMinor;
}

class _GroupedDayLedgerCard extends StatelessWidget {
  const _GroupedDayLedgerCard({
    required this.group,
    required this.currencyCode,
    required this.isDesktopTable,
    required this.hideBalances,
    required this.onTapTx,
  });

  final _LedgerDayGroup group;
  final String currencyCode;
  final bool isDesktopTable;
  final bool hideBalances;
  final ValueChanged<String> onTapTx;

  String _smartSubtitle(TransactionEntity tx, String title) {
    final parts = <String>[];
    if (tx.type == TransactionType.transfer &&
        tx.sourceAccountName != null &&
        tx.destinationAccountName != null) {
      parts.add('${tx.sourceAccountName} → ${tx.destinationAccountName}');
    } else {
      final acct = tx.sourceAccountName ?? tx.destinationAccountName;
      if (acct != null && acct.isNotEmpty) {
        parts.add(acct);
      }
      final cat = tx.categoryName ?? tx.type.label;
      if (cat.toLowerCase() != title.toLowerCase()) {
        parts.add(cat);
      }
    }
    if (parts.isEmpty) {
      parts.add(tx.type.label);
    }
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final dayNet = group.dayNetMinor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        group.header,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: cfo.surfaceTonal,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusFull,
                        ),
                      ),
                      child: Text(
                        '${group.items.length}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cfo.subtleText,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (dayNet != 0) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 136),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: dayNet > 0
                          ? cfo.incomeContainer
                          : cfo.expenseContainer,
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusFull,
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: MoneyText(
                        money: Money(
                          amountMinor: dayNet,
                          currencyCode: currencyCode,
                        ),
                        showPlusSign: true,
                        masked: hideBalances,
                        semanticKind: dayNet > 0 ? 'income' : 'expense',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            boxShadow: [
              BoxShadow(
                color: cfo.cardShadow,
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Material(
            color: cfo.surfaceElevated,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              side: BorderSide(color: cfo.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < group.items.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: isDesktopTable ? 16 : 60,
                      endIndent: 14,
                      color: cfo.divider,
                    ),
                  _buildRow(context, group.items[i]),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRow(BuildContext context, TransactionEntity tx) {
    final cfo = context.cfoColors;
    final title = tx.description?.isNotEmpty == true
        ? tx.description!
        : (tx.categoryName ?? tx.type.label);
    final subtitle = _smartSubtitle(tx, title);
    final semanticKind = switch (tx.type) {
      TransactionType.income || TransactionType.refund => 'income',
      TransactionType.expense => 'expense',
      TransactionType.transfer => 'transfer',
      _ => null,
    };
    final needsSyncPill =
        tx.syncStatus == 'pending' || tx.syncStatus == 'conflict';

    return InkWell(
      onTap: () => onTapTx(tx.id),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isDesktopTable ? AppSpacing.md : 12,
          vertical: 11,
        ),
        child: isDesktopTable
            ? Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Row(
                      children: [
                        _TransactionAvatar(type: tx.type, size: 36),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              Text(
                                tx.sourceAccountName ??
                                    tx.destinationAccountName ??
                                    tx.type.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: cfo.subtleText),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      tx.categoryName ?? tx.type.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: cfo.subtleText),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (tx.status == TransactionStatus.draft)
                          _StatusTagChip(
                            label: 'DRAFT',
                            fg: cfo.warning,
                            bg: cfo.warningContainer,
                          ),
                        if (tx.isReversed)
                          _StatusTagChip(
                            label: 'REVERSED',
                            fg: cfo.expense,
                            bg: cfo.expenseContainer,
                          ),
                        if (tx.splits.isNotEmpty)
                          _StatusTagChip(
                            label: '${tx.splits.length} SPLITS',
                            fg: cfo.transfer,
                            bg: cfo.transferContainer,
                          ),
                        if (tx.status == TransactionStatus.posted &&
                            !tx.isReversed &&
                            tx.splits.isEmpty)
                          SyncStatusBadge(status: tx.syncStatus),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: MoneyText(
                          money: tx.amount,
                          masked: hideBalances,
                          semanticKind: semanticKind,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  _TransactionAvatar(type: tx.type, size: 36),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: cfo.subtleText),
                              ),
                            ),
                            if (tx.status == TransactionStatus.draft) ...[
                              const SizedBox(width: 6),
                              _StatusTagChip(
                                label: 'DRAFT',
                                fg: cfo.warning,
                                bg: cfo.warningContainer,
                              ),
                            ],
                            if (tx.isReversed) ...[
                              const SizedBox(width: 6),
                              _StatusTagChip(
                                label: 'REVERSED',
                                fg: cfo.expense,
                                bg: cfo.expenseContainer,
                              ),
                            ],
                            if (tx.splits.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              _StatusTagChip(
                                label: '${tx.splits.length} splits',
                                fg: cfo.transfer,
                                bg: cfo.transferContainer,
                              ),
                            ],
                            if (needsSyncPill) ...[
                              const SizedBox(width: 6),
                              SyncStatusBadge(status: tx.syncStatus),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 126),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: MoneyText(
                        money: tx.amount,
                        masked: hideBalances,
                        semanticKind: semanticKind,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _LedgerPulseStrip extends StatelessWidget {
  const _LedgerPulseStrip({
    required this.totalCount,
    required this.inflow,
    required this.outflow,
    required this.net,
    required this.masked,
  });

  final int totalCount;
  final Money inflow;
  final Money outflow;
  final Money net;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final totalFlow = inflow.amountMinor + outflow.amountMinor;
    final inflowShare = totalFlow > 0
        ? (inflow.amountMinor / totalFlow).clamp(0.0, 1.0)
        : 0.0;

    return DecoratedBox(
      key: const Key('ledger_pulse_strip'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        boxShadow: [
          BoxShadow(
            color: cfo.cardShadow,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: Material(
          color: cfo.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            side: BorderSide(color: cfo.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _LedgerMiniMetric(
                        label: 'Inflow',
                        money: inflow,
                        masked: masked,
                        color: cfo.income,
                      ),
                    ),
                    Container(width: 1, height: 26, color: cfo.divider),
                    Expanded(
                      child: _LedgerMiniMetric(
                        label: 'Outflow',
                        money: outflow,
                        masked: masked,
                        color: cfo.expense,
                      ),
                    ),
                    Container(width: 1, height: 26, color: cfo.divider),
                    Expanded(
                      child: _LedgerMiniMetric(
                        label: 'Net ($totalCount)',
                        money: net,
                        masked: masked,
                        showPlusSign: true,
                        color: net.amountMinor >= 0 ? cfo.income : cfo.expense,
                      ),
                    ),
                  ],
                ),
              ),
              if (totalFlow > 0 && !masked)
                SizedBox(
                  height: 3,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (inflowShare > 0)
                        Expanded(
                          flex: (inflowShare * 1000).round().clamp(1, 1000),
                          child: ColoredBox(color: cfo.income),
                        ),
                      if (inflowShare < 1.0)
                        Expanded(
                          flex: ((1.0 - inflowShare) * 1000).round().clamp(
                            1,
                            1000,
                          ),
                          child: ColoredBox(color: cfo.expense),
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
}

class _LedgerMiniMetric extends StatelessWidget {
  const _LedgerMiniMetric({
    required this.label,
    required this.money,
    required this.masked,
    required this.color,
    this.showPlusSign = false,
  });

  final String label;
  final Money money;
  final bool masked;
  final Color color;
  final bool showPlusSign;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cfo.subtleText,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 1),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MoneyText(
              money: money,
              masked: masked,
              showPlusSign: showPlusSign,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
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
