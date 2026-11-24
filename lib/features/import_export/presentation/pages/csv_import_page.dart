import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/financial_engine/money.dart';
import '../../../../shared/widgets/enterprise_layout.dart';
import '../../../../shared/widgets/fintech_widgets.dart';
import '../../../../shared/widgets/modern_dialogs.dart';
import '../../../../shared/widgets/modern_dropdown.dart';
import '../../../accounts/domain/entities/financial_account_entity.dart';
import '../../../accounts/domain/repositories/account_repository.dart';
import '../../../categories/domain/entities/category_entity.dart';
import '../../../categories/domain/repositories/category_repository.dart';
import '../../../dashboard/presentation/bloc/dashboard_bloc.dart';
import '../../../profiles/domain/entities/profile_entity.dart';
import '../../../profiles/presentation/bloc/active_profile_cubit.dart';
import '../../../transactions/presentation/bloc/transactions_bloc.dart';
import '../../data/repositories/drift_csv_import_repository.dart';
import '../../domain/csv_import_engine.dart';

/// Covers `SCR-IMP-001` (File Selection), `SCR-IMP-002` (Column Mapping, Preview & Duplicate Review),
/// and `SCR-IMP-003` (Import Summary) (`FR-015`, `AC-CSV-001`).
class CsvImportPage extends StatefulWidget {
  const CsvImportPage({super.key});

  @override
  State<CsvImportPage> createState() => _CsvImportPageState();
}

class _CsvImportPageState extends State<CsvImportPage> {
  String? _fileName;
  String? _rawContent;
  List<List<String>> _rawRows = const [];
  List<StagedCsvRow> _stagedRows = const [];
  CsvImportSummary? _summary;
  String? _error;

  String? _accountId;
  String? _expenseCategoryId;
  String? _incomeCategoryId;
  int _dateCol = 0;
  int _descCol = 1;
  int _amountCol = 2;
  bool _hasHeader = true;
  bool _isBusy = false;

  String? _loadedProfileId;
  Future<(List<FinancialAccountEntity>, List<CategoryEntity>)>? _metadataFuture;

  Future<(List<FinancialAccountEntity>, List<CategoryEntity>)> _metadataFor(
    FinancialProfile profile,
  ) {
    if (_loadedProfileId != profile.id.value || _metadataFuture == null) {
      _loadedProfileId = profile.id.value;
      _accountId = null;
      _expenseCategoryId = null;
      _incomeCategoryId = null;
      _metadataFuture =
          Future.wait([
            GetIt.I<AccountRepository>()
                .listAccounts(profile.id)
                .then((r) => r.valueOrNull ?? const <FinancialAccountEntity>[]),
            GetIt.I<CategoryRepository>()
                .listCategories(profile.id)
                .then((r) => r.valueOrNull ?? const <CategoryEntity>[]),
          ]).then(
            (l) => (
              l[0] as List<FinancialAccountEntity>,
              l[1] as List<CategoryEntity>,
            ),
          );
    }
    return _metadataFuture!;
  }

  int get _activeStep {
    if (_summary != null || _stagedRows.isNotEmpty) return 3;
    if (_rawRows.isNotEmpty) return 2;
    return 1;
  }

  Future<void> _pickFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
    );
    if (files.isEmpty || files.first.path == null) return;
    final file = File(files.first.path!);
    final raw = await file.readAsString();
    _loadRawCsv(files.first.name, raw);
  }

  void _loadRawCsv(String name, String raw) {
    final parsed = CsvImportEngine.parseRawCsv(raw);
    if (parsed.isFailure) {
      setState(() => _error = parsed.failureOrNull!.message);
      return;
    }
    setState(() {
      _fileName = name;
      _rawContent = raw;
      _rawRows = parsed.valueOrNull!;
      _stagedRows = const [];
      _summary = null;
      _error = null;
    });
  }

  Future<void> _runPreview(FinancialProfile profile) async {
    if (_accountId == null || _rawRows.isEmpty) return;
    setState(() {
      _isBusy = true;
      _error = null;
    });
    final res = await GetIt.I<DriftCsvImportRepository>()
        .previewAndDetectDuplicates(
          profileId: profile.id,
          accountId: _accountId!,
          rawRows: _rawRows,
          mapping: CsvColumnMapping(
            dateColumnIndex: _dateCol,
            descriptionColumnIndex: _descCol,
            signedAmountColumnIndex: _amountCol,
            hasHeaderRow: _hasHeader,
            defaultCurrencyCode: profile.baseCurrencyCode,
          ),
        );
    setState(() {
      _isBusy = false;
      if (res.isSuccess) {
        _stagedRows = res.valueOrNull!;
      } else {
        _error = res.failureOrNull!.message;
      }
    });
  }

  Future<void> _commitImport(FinancialProfile profile) async {
    if (_accountId == null ||
        _expenseCategoryId == null ||
        _incomeCategoryId == null ||
        _stagedRows.isEmpty) {
      return;
    }
    setState(() {
      _isBusy = true;
      _error = null;
    });
    final res = await GetIt.I<DriftCsvImportRepository>().commitConfirmedBatch(
      profileId: profile.id,
      accountId: _accountId!,
      fileName: _fileName ?? 'statement.csv',
      rawCsvContent: _rawContent ?? '',
      reviewedRows: _stagedRows,
      defaultExpenseCategoryId: _expenseCategoryId!,
      defaultIncomeCategoryId: _incomeCategoryId!,
    );
    setState(() {
      _isBusy = false;
      if (res.isSuccess) {
        _summary = res.valueOrNull!;
      } else {
        _error = res.failureOrNull!.message;
      }
    });
    if (res.isSuccess && mounted) {
      context.read<TransactionsBloc>().add(const TransactionsLoadRequested());
      context.read<DashboardBloc>().add(const DashboardRefreshRequested());
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ActiveProfileCubit>().state.activeProfile;
    final cfo = context.cfoColors;

    if (profile == null) {
      return const Scaffold(
        body: EmptyStateView(
          icon: Icons.upload_file_outlined,
          title: 'No active profile',
          description: 'Select a profile to import CSV statements.',
        ),
      );
    }

    if (!profile.permissions.canPostTransaction) {
      return const Scaffold(
        appBar: EnterpriseAppBar(title: Text('CSV Statement Import')),
        body: EmptyStateView(
          icon: Icons.lock_outline_rounded,
          title: 'Posting permission required',
          description:
              'Your role in this workspace cannot commit CSV statement imports to the ledger.',
        ),
      );
    }

    return Scaffold(
      appBar: const EnterpriseAppBar(title: Text('CSV Statement Import')),
      body: FutureBuilder<(List<FinancialAccountEntity>, List<CategoryEntity>)>(
        future: _metadataFor(profile),
        builder: (context, snap) {
          final accounts = snap.data?.$1 ?? const [];
          final categories = snap.data?.$2 ?? const [];
          _accountId ??= accounts.firstOrNull?.id;
          _expenseCategoryId ??= categories
              .where((c) => c.categoryType == CategoryType.expense)
              .firstOrNull
              ?.id;
          _incomeCategoryId ??= categories
              .where((c) => c.categoryType == CategoryType.income)
              .firstOrNull
              ?.id;

          if (_summary != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: PressScaleCard(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconSquircle(
                        icon: Icons.check_circle_rounded,
                        iconColor: cfo.success,
                        backgroundColor: cfo.successContainer,
                        size: 64,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Import Completed',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text('Total rows: ${_summary!.totalRows}'),
                      Text(
                        'Imported into ledger: ${_summary!.importedCount}',
                        style: TextStyle(
                          color: cfo.success,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Skipped (duplicates/manual): ${_summary!.skippedCount}',
                      ),
                      Text(
                        'Rejected (validation errors): ${_summary!.rejectedCount}',
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      FilledButton(
                        onPressed: () => setState(() {
                          _summary = null;
                          _rawRows = const [];
                          _stagedRows = const [];
                          _fileName = null;
                        }),
                        child: const Text('Import Another File'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return SingleChildScrollView(
            padding: EnterprisePageContainer.responsivePadding(context),
            child: EnterprisePageContainer(
              maxWidth: AppBreakpoints.maxReadingWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StepperHeader(activeStep: _activeStep),
                  const SizedBox(height: AppSpacing.md),
                  if (_error != null) ...[
                    PressScaleCard(
                      backgroundColor: cfo.expenseContainer,
                      borderColor: cfo.expense.withValues(alpha: 0.35),
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Text(
                        _error!,
                        style: TextStyle(color: cfo.expense),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  PressScaleCard(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '1. Select CSV Statement',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Max 10 MB / 25,000 rows. Every row is previewed and checked for duplicates before committing.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: cfo.subtleText),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        if (accounts.isNotEmpty)
                          FintechDropdownField<String>(
                            label: 'Target Financial Account',
                            value: _accountId,
                            leadingIcon: Icons.account_balance_rounded,
                            options: accounts
                                .map(
                                  (a) => FintechDropdownOption<String>(
                                    value: a.id,
                                    label: a.name,
                                    selectedLabel:
                                        '${a.name} (${a.currencyCode})',
                                    subtitle: a.accountType.label,
                                    badge: a.currencyCode,
                                    icon: Icons.account_balance_wallet_outlined,
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() => _accountId = v),
                          ),
                        const SizedBox(height: AppSpacing.sm),
                        FilledButton.icon(
                          onPressed: _pickFile,
                          icon: const Icon(Icons.folder_open_outlined),
                          label: Text(
                            _fileName == null
                                ? 'Choose CSV File'
                                : 'Selected: $_fileName (${_rawRows.length} rows)',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_rawRows.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    PressScaleCard(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '2. Map Columns',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          _colDropdown(
                            'Date column',
                            _dateCol,
                            (v) => setState(() => _dateCol = v),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          _colDropdown(
                            'Description column',
                            _descCol,
                            (v) => setState(() => _descCol = v),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          _colDropdown(
                            'Signed Amount column (- expense / + income)',
                            _amountCol,
                            (v) => setState(() => _amountCol = v),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          FintechSwitchCard(
                            icon: Icons.table_rows_outlined,
                            title: 'First row contains column headers',
                            value: _hasHeader,
                            onChanged: (v) => setState(() => _hasHeader = v),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          FilledButton(
                            onPressed: _isBusy
                                ? null
                                : () => _runPreview(profile),
                            child: const Text('Preview & Detect Duplicates'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_stagedRows.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    _buildPreviewSummaryCard(context, profile),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _colDropdown(String label, int value, ValueChanged<int> onChanged) {
    final colCount = _rawRows.first.length;
    final clamped = value < colCount ? value : 0;
    return FintechDropdownField<int>(
      label: label,
      value: clamped,
      leadingIcon: Icons.view_column_outlined,
      options: List.generate(
        colCount,
        (i) => FintechDropdownOption<int>(
          value: i,
          label: 'Col ${i + 1}: ${_rawRows.first[i]}',
          badge: '#${i + 1}',
        ),
      ),
      onChanged: onChanged,
    );
  }

  Widget _buildPreviewSummaryCard(
    BuildContext context,
    FinancialProfile profile,
  ) {
    final cfo = context.cfoColors;
    final validCount = _stagedRows
        .where((r) => r.validationStatus == StagedRowValidationStatus.valid)
        .length;
    final dupCount = _stagedRows
        .where(
          (r) =>
              r.validationStatus == StagedRowValidationStatus.possibleDuplicate,
        )
        .length;
    final invalidCount = _stagedRows
        .where((r) => r.validationStatus == StagedRowValidationStatus.invalid)
        .length;

    return PressScaleCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '3. Review & Confirm',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: 4,
            children: [
              _StatPill(
                label: 'Valid: $validCount',
                fg: cfo.income,
                bg: cfo.incomeContainer,
              ),
              _StatPill(
                label: 'Duplicates: $dupCount',
                fg: cfo.warning,
                bg: cfo.warningContainer,
              ),
              _StatPill(
                label: 'Invalid: $invalidCount',
                fg: cfo.expense,
                bg: cfo.expenseContainer,
              ),
            ],
          ),
          const Divider(height: 20),
          for (var i = 0; i < _stagedRows.length && i < 30; i++) ...[
            _buildStagedRowTile(i, _stagedRows[i]),
          ],
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: _isBusy ? null : () => _commitImport(profile),
            icon: const Icon(Icons.check_rounded),
            label: const Text('Confirm & Commit Batch to Ledger'),
          ),
        ],
      ),
    );
  }

  Widget _buildStagedRowTile(int idx, StagedCsvRow row) {
    final cfo = context.cfoColors;
    final isDup =
        row.validationStatus == StagedRowValidationStatus.possibleDuplicate;
    final isInvalid = row.validationStatus == StagedRowValidationStatus.invalid;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Row #${row.sourceRowNumber}: ${row.description ?? '(no description)'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  isInvalid
                      ? row.validationMessage ?? 'Invalid row'
                      : '${row.transactionDateUtc?.substring(0, 10) ?? ''} • ${row.amountMinor != null && row.currencyCode != null ? Money(amountMinor: row.amountMinor!, currencyCode: row.currencyCode!).format() : ''}${isDup ? ' • Possible duplicate' : ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isInvalid
                        ? cfo.expense
                        : (isDup ? cfo.warning : cfo.subtleText),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isInvalid)
            FintechStatusPill(
              label: 'Reject',
              foreground: cfo.expense,
              background: cfo.expenseContainer,
            )
          else
            Switch(
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              value: row.decision == StagedRowDecision.importRow,
              onChanged: (importIt) {
                setState(() {
                  _stagedRows[idx] = row.copyWith(
                    decision: importIt
                        ? StagedRowDecision.importRow
                        : StagedRowDecision.skip,
                  );
                });
              },
            ),
        ],
      ),
    );
  }
}

class _StepperHeader extends StatelessWidget {
  const _StepperHeader({required this.activeStep});
  final int activeStep;

  @override
  Widget build(BuildContext context) {
    final steps = const ['1. File', '2. Columns', '3. Commit'];
    final scheme = Theme.of(context).colorScheme;
    final cfo = context.cfoColors;

    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
              decoration: BoxDecoration(
                color: (i + 1) <= activeStep
                    ? scheme.primaryContainer
                    : cfo.surfaceTonal,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Text(
                steps[i],
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: (i + 1) <= activeStep
                      ? scheme.onPrimaryContainer
                      : cfo.subtleText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (i < steps.length - 1) const SizedBox(width: AppSpacing.xs),
        ],
      ],
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.fg, required this.bg});
  final String label;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
