import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../../core/financial_engine/currency.dart';
import '../../core/financial_engine/money.dart';
import '../../features/accounts/domain/entities/financial_account_entity.dart';
import 'modern_dialogs.dart';
import 'modern_dropdown.dart';
import 'modern_inputs.dart';

typedef CreditSalaryDraft = ({
  int amountMinor,
  String accountId,
  bool createRecurringRule,
});

/// Modern reusable dialog for crediting planned monthly salary into a real
/// bank/cash account (`TransactionType.income`) with optional recurring reminder.
class CreditSalaryDialog extends StatefulWidget {
  const CreditSalaryDialog({
    required this.currencyCode,
    required this.monthLabel,
    required this.defaultAmountMinor,
    required this.accounts,
    this.preferredAccountId,
    this.alreadyCredited = false,
    super.key,
  });

  final String currencyCode;
  final String monthLabel;
  final int defaultAmountMinor;
  final List<FinancialAccountEntity> accounts;
  final String? preferredAccountId;
  final bool alreadyCredited;

  @override
  State<CreditSalaryDialog> createState() => _CreditSalaryDialogState();
}

class _CreditSalaryDialogState extends State<CreditSalaryDialog> {
  late final TextEditingController _amountCtrl;
  late String _accountId;
  bool _createRecurringRule = true;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(
      text: _minorToPlain(widget.defaultAmountMinor),
    );
    final preferred = widget.preferredAccountId;
    if (preferred != null && widget.accounts.any((a) => a.id == preferred)) {
      _accountId = preferred;
    } else {
      _accountId = widget.accounts.first.id;
    }
    _createRecurringRule = !widget.alreadyCredited;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  String _minorToPlain(int minor) {
    if (minor <= 0) return '';
    final spec = CurrencyCatalog.requireByCode(widget.currencyCode);
    final factor = math.pow(10, spec.minorUnit).toInt();
    if (spec.minorUnit == 0) return '$minor';
    if (minor % factor == 0) return '${minor ~/ factor}';
    return (minor / factor).toStringAsFixed(spec.minorUnit);
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
    final cfo = context.cfoColors;
    final amtMinor = _parseMinor(_amountCtrl.text);
    final valid = amtMinor > 0 && widget.accounts.isNotEmpty;

    return ModernDialogShell(
      title: widget.alreadyCredited
          ? 'Credit Extra Pay (${widget.monthLabel})'
          : 'Credit Salary (${widget.monthLabel})',
      subtitle:
          'Deposits real income into your account & updates Dashboard, Ledger & Monthly Tracker.',
      icon: Icons.account_balance_rounded,
      accent: ModernDialogAccent.success,
      confirmLabel: widget.alreadyCredited ? 'Post Income' : 'Credit to Bank',
      confirmKey: const Key('credit_salary_confirm_btn'),
      onConfirm: valid
          ? () => Navigator.of(context).pop<CreditSalaryDraft>((
              amountMinor: amtMinor,
              accountId: _accountId,
              createRecurringRule: _createRecurringRule,
            ))
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FintechTextField(
            key: const Key('credit_salary_amount_field'),
            label: 'Net Salary Amount (${widget.currencyCode})',
            controller: _amountCtrl,
            compact: true,
            leadingIcon: Icons.payments_outlined,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          FintechDropdownField<String>(
            key: const Key('credit_salary_account_dropdown'),
            label: 'Deposit To Account',
            value: _accountId,
            leadingIcon: Icons.account_balance_wallet_outlined,
            compact: true,
            options: [
              for (final a in widget.accounts)
                FintechDropdownOption<String>(
                  value: a.id,
                  label: a.name,
                  subtitle:
                      '${a.accountType.label} • Bal ${a.balance.format()}',
                ),
            ],
            onChanged: (v) => setState(() => _accountId = v),
          ),
          const SizedBox(height: 10),
          Material(
            color: cfo.surfaceTonal,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              side: BorderSide(color: cfo.divider),
            ),
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile.adaptive(
              key: const Key('credit_salary_recurring_switch'),
              dense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 2,
              ),
              title: Text(
                'Auto-remind every month',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                'Creates a monthly salary recurring draft on the 1st',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
              ),
              value: _createRecurringRule,
              onChanged: (v) => setState(() => _createRecurringRule = v),
            ),
          ),
        ],
      ),
    );
  }
}
