import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/financial_engine/currency.dart';
import '../../../../core/financial_engine/loan_amortizer.dart';
import '../../../../core/financial_engine/money.dart';
import '../../../../core/utilities/clock.dart';
import '../../../../shared/widgets/enterprise_layout.dart';
import '../../../../shared/widgets/fintech_widgets.dart';
import '../../../../shared/widgets/modern_dialogs.dart';
import '../../../../shared/widgets/modern_dropdown.dart';
import '../../../../shared/widgets/modern_inputs.dart';
import '../../../accounts/domain/entities/financial_account_entity.dart';
import '../../../accounts/domain/repositories/account_repository.dart';
import '../../../dashboard/presentation/bloc/dashboard_bloc.dart';
import '../../../profiles/domain/entities/profile_entity.dart';
import '../../../profiles/presentation/bloc/active_profile_cubit.dart';
import '../../../settings/presentation/bloc/settings_cubit.dart';
import '../../data/repositories/drift_loan_repository.dart';
import '../../domain/entities/loan_entity.dart';

/// `SCR-LOAN-001` — Loans & Reducing-Balance EMI Installment Manager (`FR-018`).
class LoansPage extends StatefulWidget {
  const LoansPage({super.key});

  @override
  State<LoansPage> createState() => _LoansPageState();
}

class _LoansPageState extends State<LoansPage> {
  List<LoanEntity>? _loans;
  bool _loading = true;
  String? _loadedProfileId;

  Future<void> _reload(FinancialProfile profile) async {
    _loadedProfileId = profile.id.value;
    setState(() => _loading = true);
    final res = await GetIt.I<DriftLoanRepository>().listLoans(profile.id);
    if (!mounted) return;
    setState(() {
      _loans = res.valueOrNull ?? const [];
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
          icon: Icons.request_quote_outlined,
          title: 'No active profile',
          description: 'Select a profile to track loans.',
        ),
      );
    }
    if (_loadedProfileId != profile.id.value) {
      _loadedProfileId = profile.id.value;
      Future.microtask(() => _reload(profile));
    }

    final repo = GetIt.I<DriftLoanRepository>();
    final loans = _loans ?? const [];
    final hasLoans = loans.isNotEmpty;
    final canPost = profile.permissions.canPostTransaction;

    return Scaffold(
      appBar: const EnterpriseAppBar(title: Text('Loans & Installments')),
      floatingActionButton: hasLoans && canPost
          ? FloatingActionButton.extended(
              onPressed: () => _openCreateLoanSheet(context, profile, repo),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Loan'),
            )
          : null,
      body: _loading && _loans == null
          ? const DashboardSkeletonView()
          : !hasLoans
          ? EmptyStateView(
              icon: Icons.request_quote_outlined,
              title: 'No loans tracked',
              description:
                  'Track mortgages, vehicle loans, or business credit with exact Reducing-Balance EMI amortization splitting Principal, Interest, and Fees.',
              actionLabel: canPost ? 'Add Loan' : null,
              onAction: canPost
                  ? () => _openCreateLoanSheet(context, profile, repo)
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
                      for (var i = 0; i < loans.length; i++) ...[
                        StaggeredFadeSlide(
                          index: i,
                          child: _LoanCard(
                            loan: loans[i],
                            masked: hideBalances,
                            canPost: canPost,
                            onPayInstallment: (inst) => _payInstallment(
                              context,
                              profile,
                              repo,
                              loans[i],
                              inst,
                            ),
                          ),
                        ),
                        if (i < loans.length - 1)
                          const SizedBox(height: AppSpacing.sm),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Future<void> _openCreateLoanSheet(
    BuildContext context,
    FinancialProfile profile,
    DriftLoanRepository repo,
  ) async {
    final accs =
        (await GetIt.I<AccountRepository>().listAccounts(
          profile.id,
        )).valueOrNull?.where((a) => !a.isLiability).toList() ??
        const <FinancialAccountEntity>[];
    if (!context.mounted) return;
    await showEnterpriseModal<void>(
      context: context,
      maxWidth: 520,
      builder: (_) => _CreateLoanSheetBody(
        profile: profile,
        repo: repo,
        assetAccounts: accs,
        onSaved: () => _reload(profile),
      ),
    );
  }

  Future<void> _payInstallment(
    BuildContext context,
    FinancialProfile profile,
    DriftLoanRepository repo,
    LoanEntity loan,
    LoanInstallmentEntity inst,
  ) async {
    final accs =
        (await GetIt.I<AccountRepository>().listAccounts(
          profile.id,
        )).valueOrNull?.where((a) => !a.isLiability).toList() ??
        const <FinancialAccountEntity>[];
    if (!context.mounted) return;
    if (accs.isEmpty) {
      showFintechToast(
        context,
        'Add a bank or cash asset account to pay an EMI.',
        tone: FintechToastTone.warning,
      );
      return;
    }

    final defaultAccId =
        loan.fundingAccountId != null &&
            accs.any((a) => a.id == loan.fundingAccountId)
        ? loan.fundingAccountId!
        : accs.first.id;
    final result = await showModernDialog<bool>(
      context: context,
      builder: (_) => _PayInstallmentDialog(
        profile: profile,
        repo: repo,
        loan: loan,
        inst: inst,
        assetAccounts: accs,
        initialBankAccountId: defaultAccId,
      ),
    );
    if (result == true && context.mounted) {
      context.read<DashboardBloc>().add(const DashboardRefreshRequested());
      await _reload(profile);
    }
  }
}

class _LoanCard extends StatefulWidget {
  const _LoanCard({
    required this.loan,
    required this.masked,
    required this.canPost,
    required this.onPayInstallment,
  });

  final LoanEntity loan;
  final bool masked;
  final bool canPost;
  final ValueChanged<LoanInstallmentEntity> onPayInstallment;

  @override
  State<_LoanCard> createState() => _LoanCardState();
}

class _LoanCardState extends State<_LoanCard> {
  bool _expanded = false;

  /// `0` = all installments; `1..N` = 1-based year slice (12 installments/year).
  late int _selectedYear;

  @override
  void initState() {
    super.initState();
    _selectedYear = _initialYearFor(widget.loan);
  }

  @override
  void didUpdateWidget(covariant _LoanCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loan.id != widget.loan.id) {
      _selectedYear = _initialYearFor(widget.loan);
    }
  }

  int _initialYearFor(LoanEntity loan) {
    if (loan.installments.length <= 12) return 0;
    final firstUnpaid = loan.installments
        .where((i) => i.status != 'paid')
        .firstOrNull;
    if (firstUnpaid == null) return 1;
    return ((firstUnpaid.installmentNumber - 1) ~/ 12) + 1;
  }

  @override
  Widget build(BuildContext context) {
    final loan = widget.loan;
    final masked = widget.masked;
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final curr = loan.principal.currencyCode;
    final totalPrin = loan.principal.amountMinor;
    final paidPrin = totalPrin - loan.remainingPrincipalMinor;
    final payoffRatio = totalPrin > 0
        ? (paidPrin / totalPrin).clamp(0.0, 1.0)
        : 0.0;
    final paidCount = loan.installments.where((i) => i.status == 'paid').length;
    final isPaidOff =
        loan.status == 'paid_off' ||
        (loan.installments.isNotEmpty && paidCount == loan.installments.length);

    final totalYears = (loan.installments.length / 12).ceil();
    final visibleInstallments = _selectedYear == 0 || totalYears <= 1
        ? loan.installments
        : loan.installments.where((inst) {
            final start = (_selectedYear - 1) * 12 + 1;
            final end = _selectedYear * 12;
            return inst.installmentNumber >= start &&
                inst.installmentNumber <= end;
          }).toList();

    final remainingMoney = Money(
      amountMinor: loan.remainingPrincipalMinor,
      currencyCode: curr,
    );

    return PressScaleCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: Key('loan_header_${loan.id}'),
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _expanded = !_expanded);
              },
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconSquircle(
                          icon: isPaidOff
                              ? Icons.verified_rounded
                              : Icons.request_quote_rounded,
                          iconColor: isPaidOff ? cfo.success : cfo.warning,
                          backgroundColor: isPaidOff
                              ? cfo.successContainer
                              : cfo.warningContainer,
                          size: 40,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      loan.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  FintechStatusPill(
                                    label: isPaidOff
                                        ? 'Paid Off'
                                        : '$paidCount/${loan.installments.length} EMIs',
                                    foreground: isPaidOff
                                        ? cfo.success
                                        : scheme.primary,
                                    background: isPaidOff
                                        ? cfo.successContainer
                                        : scheme.primaryContainer,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                masked
                                    ? 'Remaining: •••• • ${(loan.annualInterestRateBps / 100).toStringAsFixed(2)}% p.a.'
                                    : 'Remaining: ${remainingMoney.format()} / ${loan.principal.format()} • ${(loan.annualInterestRateBps / 100).toStringAsFixed(2)}% p.a.',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: cfo.subtleText,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        AnimatedRotation(
                          turns: _expanded ? 0.5 : 0.0,
                          duration: AppMotion.resolve(context, AppMotion.fast),
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: cfo.subtleText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: AnimatedProgressBar(
                            value: masked ? 0.0 : payoffRatio,
                            color: isPaidOff ? cfo.success : cfo.income,
                            height: 6,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          masked ? '••%' : '${(payoffRatio * 100).round()}%',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: isPaidOff ? cfo.success : cfo.income,
                                fontWeight: FontWeight.w800,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(height: 1, color: cfo.divider),
            if (totalYears > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var yr = 1; yr <= totalYears; yr++) ...[
                        _LoanYearPill(
                          label: 'Year $yr',
                          selected: _selectedYear == yr,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _selectedYear = yr);
                          },
                        ),
                        const SizedBox(width: 6),
                      ],
                      _LoanYearPill(
                        key: Key('loan_show_all_${loan.id}'),
                        label: 'All (${loan.installments.length})',
                        selected: _selectedYear == 0,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedYear = 0);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            for (var idx = 0; idx < visibleInstallments.length; idx++) ...[
              if (idx > 0)
                Divider(
                  height: 1,
                  indent: 14,
                  endIndent: 14,
                  color: cfo.divider,
                ),
              _InstallmentRow(
                inst: visibleInstallments[idx],
                currencyCode: curr,
                masked: masked,
                canPost: widget.canPost,
                onPay: () => widget.onPayInstallment(visibleInstallments[idx]),
              ),
            ],
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _LoanYearPill extends StatelessWidget {
  const _LoanYearPill({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cfo = context.cfoColors;
    return Material(
      color: selected ? scheme.primaryContainer : cfo.surfaceTonal,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        side: BorderSide(color: selected ? scheme.primary : cfo.divider),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: selected ? scheme.onPrimaryContainer : cfo.subtleText,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _InstallmentRow extends StatelessWidget {
  const _InstallmentRow({
    required this.inst,
    required this.currencyCode,
    required this.masked,
    required this.canPost,
    required this.onPay,
  });

  final LoanInstallmentEntity inst;
  final String currencyCode;
  final bool masked;
  final bool canPost;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final paid = inst.status == 'paid';
    final prinText = Money(
      amountMinor: inst.principalDueMinor,
      currencyCode: currencyCode,
    ).format(mask: masked);
    final intText = Money(
      amountMinor: inst.interestDueMinor,
      currencyCode: currencyCode,
    ).format(mask: masked);
    final feeSuffix = inst.feeDueMinor > 0
        ? ' + Fee ${Money(amountMinor: inst.feeDueMinor, currencyCode: currencyCode).format(mask: masked)}'
        : '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'EMI #${inst.installmentNumber} • Due ${UiDateFormatter.shortDayMonthYear(inst.dueDateUtc)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Principal $prinText + Interest $intText$feeSuffix',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cfo.subtleText,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (paid)
            FintechStatusPill(
              label: 'Paid',
              showDot: true,
              foreground: cfo.success,
              background: cfo.successContainer,
            )
          else if (canPost)
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onPay,
              child: const Text('Pay EMI'),
            )
          else
            FintechStatusPill(
              label: 'Scheduled',
              foreground: cfo.subtleText,
              background: cfo.surfaceTonal,
            ),
        ],
      ),
    );
  }
}

class _PayInstallmentDialog extends StatefulWidget {
  const _PayInstallmentDialog({
    required this.profile,
    required this.repo,
    required this.loan,
    required this.inst,
    required this.assetAccounts,
    required this.initialBankAccountId,
  });

  final FinancialProfile profile;
  final DriftLoanRepository repo;
  final LoanEntity loan;
  final LoanInstallmentEntity inst;
  final List<FinancialAccountEntity> assetAccounts;
  final String initialBankAccountId;

  @override
  State<_PayInstallmentDialog> createState() => _PayInstallmentDialogState();
}

class _PayInstallmentDialogState extends State<_PayInstallmentDialog> {
  late String _bankAccId;
  final _feeCtrl = TextEditingController();
  String? _errorMsg;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _bankAccId = widget.initialBankAccountId;
  }

  @override
  void dispose() {
    _feeCtrl.dispose();
    super.dispose();
  }

  int _parseFeeMinor() {
    final raw = _feeCtrl.text.trim();
    if (raw.isEmpty) return 0;
    final curr = CurrencyCatalog.requireByCode(
      widget.loan.principal.currencyCode,
    );
    return Money.parseDecimal(raw, currency: curr).valueOrNull?.amountMinor ??
        -1;
  }

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final feeMinor = _parseFeeMinor();
    final totalWithFee =
        widget.inst.totalDueMinor + (feeMinor > 0 ? feeMinor : 0);

    return ModernDialogShell(
      title: 'Pay EMI #${widget.inst.installmentNumber}',
      subtitle:
          'Double-entry Principal, Interest & Fee split for ${widget.loan.name}',
      icon: Icons.payments_rounded,
      accent: ModernDialogAccent.success,
      confirmLabel: _submitting ? 'Paying...' : 'Confirm Payment',
      onConfirm: _submitting
          ? null
          : () async {
              final parsedFee = _parseFeeMinor();
              if (parsedFee < 0) {
                setState(
                  () => _errorMsg = 'Enter a valid non-negative fee amount.',
                );
                return;
              }
              setState(() {
                _submitting = true;
                _errorMsg = null;
              });
              final res = await widget.repo.payInstallment(
                profileId: widget.profile.id,
                loanId: widget.loan.id,
                installmentId: widget.inst.id,
                sourceBankAccountId: _bankAccId,
                feeMinor: parsedFee,
              );
              if (!context.mounted) return;
              if (res.isFailure) {
                setState(() {
                  _submitting = false;
                  _errorMsg = res.failureOrNull!.message;
                });
                return;
              }
              showFintechToast(
                context,
                'Installment paid with Principal/Interest double-entry split.',
                tone: FintechToastTone.success,
              );
              Navigator.of(context).pop(true);
            },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_errorMsg != null) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.xs),
              decoration: BoxDecoration(
                color: cfo.expenseContainer,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Text(
                _errorMsg!,
                style: TextStyle(
                  color: cfo.expense,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: cfo.surfaceTonal,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: cfo.divider.withValues(alpha: 0.7)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total EMI Due',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: cfo.subtleText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                MoneyText(
                  money: Money(
                    amountMinor: totalWithFee,
                    currencyCode: widget.loan.principal.currencyCode,
                  ),
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FintechDropdownField<String>(
            label: 'Pay From Account',
            value: _bankAccId,
            leadingIcon: Icons.account_balance_outlined,
            options: widget.assetAccounts
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
            onChanged: (v) => setState(() => _bankAccId = v),
          ),
          const SizedBox(height: 10),
          FintechTextField(
            key: const Key('pay_emi_fee_field'),
            label:
                'Late / Processing Fee (${widget.loan.principal.currencyCode}, optional)',
            controller: _feeCtrl,
            compact: true,
            leadingIcon: Icons.receipt_long_outlined,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() => _errorMsg = null),
          ),
        ],
      ),
    );
  }
}

class _CreateLoanSheetBody extends StatefulWidget {
  const _CreateLoanSheetBody({
    required this.profile,
    required this.repo,
    required this.assetAccounts,
    required this.onSaved,
  });

  final FinancialProfile profile;
  final DriftLoanRepository repo;
  final List<FinancialAccountEntity> assetAccounts;
  final Future<void> Function() onSaved;

  @override
  State<_CreateLoanSheetBody> createState() => _CreateLoanSheetBodyState();
}

class _CreateLoanSheetBodyState extends State<_CreateLoanSheetBody> {
  final _nameCtrl = TextEditingController();
  final _principalCtrl = TextEditingController();
  final _rateCtrl = TextEditingController(text: '10.5');
  final _monthsCtrl = TextEditingController(text: '12');
  var _method = LoanInterestMethod.reducingBalance;
  late DateTime _startDateUtc;
  String? _fundingAccountId;
  String? _errorMsg;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _startDateUtc = GetIt.I<UtcClock>().nowUtc();
    _fundingAccountId = widget.assetAccounts.firstOrNull?.id;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _principalCtrl.dispose();
    _rateCtrl.dispose();
    _monthsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final local = _startDateUtc.toLocal();
    final picked = await showDatePicker(
      context: context,
      initialDate: local,
      firstDate: DateTime(2000),
      lastDate: DateTime(local.year + 10, 12, 31),
    );
    if (picked != null && mounted) {
      setState(() {
        _startDateUtc = DateTime.utc(picked.year, picked.month, picked.day);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final cfo = context.cfoColors;
    final curr = CurrencyCatalog.requireByCode(profile.baseCurrencyCode);
    final parsedPrin = Money.parseDecimal(
      _principalCtrl.text.trim(),
      currency: curr,
    ).valueOrNull?.amountMinor;
    final ratePct = double.tryParse(_rateCtrl.text.trim()) ?? -1;
    final term = int.tryParse(_monthsCtrl.text.trim()) ?? 0;

    List<LoanInstallmentPlan>? preview;
    if (parsedPrin != null &&
        parsedPrin > 0 &&
        ratePct >= 0 &&
        term > 0 &&
        term <= 600) {
      preview = LoanAmortizer.generateSchedule(
        principalMinor: parsedPrin,
        annualInterestRateBps: (ratePct * 100).round(),
        termMonths: term,
        startDateUtc: _startDateUtc,
        method: _method,
      );
    }

    final monthlyEmiMinor = preview?.first.totalPaymentMinor ?? 0;
    final totalInterestMinor =
        preview?.fold<int>(0, (s, p) => s + p.interestDueMinor) ?? 0;

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
                title: 'Add Loan & EMI Schedule',
                subtitle: 'Automatic principal/interest/fee breakdown.',
                icon: Icons.request_quote_rounded,
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
                label: 'Loan Name (e.g., Car Loan)',
                controller: _nameCtrl,
                leadingIcon: Icons.request_quote_outlined,
                textCapitalization: TextCapitalization.words,
                showClearButton: true,
                onChanged: (_) => setState(() => _errorMsg = null),
              ),
              const SizedBox(height: AppSpacing.sm),
              FintechTextField(
                label: 'Principal (${profile.baseCurrencyCode})',
                controller: _principalCtrl,
                leadingIcon: Icons.payments_outlined,
                onChanged: (_) => setState(() => _errorMsg = null),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: FintechTextField(
                      label: 'Annual Rate (%)',
                      controller: _rateCtrl,
                      compact: true,
                      onChanged: (_) => setState(() => _errorMsg = null),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FintechTextField(
                      label: 'Term (Months)',
                      controller: _monthsCtrl,
                      compact: true,
                      onChanged: (_) => setState(() => _errorMsg = null),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              FintechSegmentedControl<LoanInterestMethod>(
                key: const Key('loan_method_segmented'),
                selected: _method,
                options: const [
                  FintechSegmentOption(
                    value: LoanInterestMethod.reducingBalance,
                    label: 'Reducing Balance',
                  ),
                  FintechSegmentOption(
                    value: LoanInterestMethod.flat,
                    label: 'Flat Rate',
                  ),
                ],
                onChanged: (m) => setState(() => _method = m),
              ),
              const SizedBox(height: AppSpacing.sm),
              Material(
                color: cfo.surfaceTonal,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  side: BorderSide(color: cfo.divider),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  onTap: _pickStartDate,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.event_rounded,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Disbursement / Start Date',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: cfo.subtleText),
                              ),
                              Text(
                                UiDateFormatter.shortDayMonthYear(
                                  _startDateUtc.toIso8601String(),
                                ),
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.edit_calendar_rounded,
                          size: 17,
                          color: cfo.subtleText,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (widget.assetAccounts.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                FintechDropdownField<String?>(
                  label: 'Default Repayment Account (optional)',
                  value: _fundingAccountId,
                  leadingIcon: Icons.account_balance_outlined,
                  options: [
                    const FintechDropdownOption<String?>(
                      value: null,
                      label: 'Ask on each EMI',
                      icon: Icons.help_outline_rounded,
                    ),
                    ...widget.assetAccounts.map(
                      (a) => FintechDropdownOption<String?>(
                        value: a.id,
                        label: a.name,
                        subtitle: a.accountType.label,
                        badge: a.currencyCode,
                        icon: Icons.account_balance_rounded,
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _fundingAccountId = v),
                ),
              ],
              if (preview != null) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: cfo.surfaceTonal,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Estimated Monthly EMI',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: cfo.subtleText),
                            ),
                            Text(
                              Money(
                                amountMinor: monthlyEmiMinor,
                                currencyCode: profile.baseCurrencyCode,
                              ).format(),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Total Interest',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: cfo.subtleText),
                            ),
                            Text(
                              Money(
                                amountMinor: totalInterestMinor,
                                currencyCode: profile.baseCurrencyCode,
                              ).format(),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: cfo.warning,
                                    fontWeight: FontWeight.w700,
                                    fontFeatures: const [
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
              FilledButton(
                onPressed: _saving
                    ? null
                    : () async {
                        if (_nameCtrl.text.trim().isEmpty) {
                          setState(
                            () => _errorMsg = 'Please enter a loan name.',
                          );
                          return;
                        }
                        final prin = Money.parseDecimal(
                          _principalCtrl.text,
                          currency: curr,
                        );
                        if (prin.isFailure ||
                            (prin.valueOrNull?.amountMinor ?? 0) <= 0) {
                          setState(
                            () => _errorMsg =
                                'Enter a valid positive principal amount.',
                          );
                          return;
                        }
                        final rPct = double.tryParse(_rateCtrl.text.trim());
                        if (rPct == null || rPct < 0 || rPct > 100) {
                          setState(
                            () => _errorMsg =
                                'Annual interest rate must be between 0% and 100%.',
                          );
                          return;
                        }
                        final trm = int.tryParse(_monthsCtrl.text.trim()) ?? 0;
                        if (trm <= 0 || trm > 600) {
                          setState(
                            () => _errorMsg =
                                'Loan term must be between 1 and 600 months.',
                          );
                          return;
                        }
                        setState(() {
                          _saving = true;
                          _errorMsg = null;
                        });
                        final res = await widget.repo.createLoan(
                          profileId: profile.id,
                          name: _nameCtrl.text.trim(),
                          principalMinor: prin.valueOrNull!.amountMinor,
                          currencyCode: profile.baseCurrencyCode,
                          annualInterestRateBps: (rPct * 100).round(),
                          termMonths: trm,
                          startDateUtc: _startDateUtc,
                          method: _method,
                          fundingAccountId: _fundingAccountId,
                        );
                        if (!context.mounted) return;
                        if (res.isFailure) {
                          setState(() {
                            _saving = false;
                            _errorMsg = res.failureOrNull!.message;
                          });
                          return;
                        }
                        context.read<DashboardBloc>().add(
                          const DashboardRefreshRequested(),
                        );
                        Navigator.of(context).pop();
                        await widget.onSaved();
                      },
                child: const Text('Create Loan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
