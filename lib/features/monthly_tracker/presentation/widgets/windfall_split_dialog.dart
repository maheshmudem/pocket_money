import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/financial_engine/currency.dart';
import '../../../../core/financial_engine/money.dart';
import '../../../../core/financial_engine/monthly_tracker_engine.dart';
import '../../../../shared/widgets/modern_dialogs.dart';
import '../../../../shared/widgets/modern_dropdown.dart';
import '../../../../shared/widgets/modern_inputs.dart';
import '../../../../shared/widgets/trendy_fintech_gauges.dart';
import '../../../accounts/domain/entities/financial_account_entity.dart';
import '../../../savings_goals/domain/entities/savings_goal_entity.dart';

/// Output payload produced by [WindfallSplitDialog].
final class WindfallDraft {
  const WindfallDraft({
    required this.amountMinor,
    required this.sourceLabel,
    required this.accountId,
    required this.split,
    this.goalId,
  });

  final int amountMinor;
  final String sourceLabel;
  final String accountId;
  final WindfallSplit split;
  final String? goalId;
}

/// Interactive Extra / Windfall Income split dialog enforcing exact 100% allocation
/// across Future Savings Goals, Planned Bucket Items, and This Month Spend.
class WindfallSplitDialog extends StatefulWidget {
  const WindfallSplitDialog({
    required this.currencyCode,
    required this.snapshot,
    required this.accounts,
    required this.goals,
    this.initialAmountMinor,
    this.initialSourceLabel,
    this.initialPreset,
    super.key,
  });

  final String currencyCode;
  final MonthlyTrackerSnapshot snapshot;
  final List<FinancialAccountEntity> accounts;
  final List<SavingsGoalEntity> goals;
  final int? initialAmountMinor;
  final String? initialSourceLabel;
  final String? initialPreset;

  @override
  State<WindfallSplitDialog> createState() => _WindfallSplitDialogState();
}

class _WindfallSplitDialogState extends State<WindfallSplitDialog> {
  static const _newFutureFundSentinel = '__new_future_fund__';
  static const _sources = [
    'Bonus',
    'Freelance',
    'Gift',
    'Cashback',
    'Interest',
    'Other',
  ];

  final _amountCtrl = TextEditingController();
  final _saveCtrl = TextEditingController(text: '0');
  final _bucketCtrl = TextEditingController(text: '0');
  final _spendCtrl = TextEditingController(text: '0');

  String _sourceLabel = 'Bonus';
  late String _accountId;
  String _selectedGoalId = _newFutureFundSentinel;
  String _rationale = 'Enter an extra income amount to auto-split.';
  bool _programmatic = false;

  @override
  void initState() {
    super.initState();
    _accountId = widget.accounts.isNotEmpty ? widget.accounts.first.id : '';
    if (widget.goals.isNotEmpty) {
      _selectedGoalId = widget.goals.first.id;
    }
    if (widget.initialSourceLabel != null &&
        _sources.contains(widget.initialSourceLabel)) {
      _sourceLabel = widget.initialSourceLabel!;
    }
    if (widget.initialAmountMinor != null && widget.initialAmountMinor! > 0) {
      final amt = widget.initialAmountMinor!;
      _amountCtrl.text = _minorToPlain(amt);
      final split = switch (widget.initialPreset) {
        '50_30_20' => MonthlyTrackerEngine.presetSplit(amt, 50, 30),
        'save_all' => MonthlyTrackerEngine.presetSplit(amt, 100, 0),
        'bucket_first' => MonthlyTrackerEngine.presetSplit(amt, 30, 70),
        _ => MonthlyTrackerEngine.suggestWindfallSplit(
          amountMinor: amt,
          monthGapMinor: math.max<int>(0, -widget.snapshot.freeToSpendMinor),
          urgentShortfallMinor: widget.snapshot.bucketPlan.urgentShortfallMinor,
          essentialUnfundedMinor:
              widget.snapshot.bucketPlan.essentialUnfundedMinor,
          currencyCode: widget.currencyCode,
        ),
      };
      _programmatic = true;
      _saveCtrl.text = _minorToPlain(split.toSavingsMinor);
      _bucketCtrl.text = _minorToPlain(split.toBucketMinor);
      _spendCtrl.text = _minorToPlain(split.toSpendMinor);
      _programmatic = false;
      _rationale = split.rationale;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _saveCtrl.dispose();
    _bucketCtrl.dispose();
    _spendCtrl.dispose();
    super.dispose();
  }

  String _minorToPlain(int minor) {
    if (minor <= 0) return '0';
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

  void _applySplit(WindfallSplit split) {
    _programmatic = true;
    _saveCtrl.text = _minorToPlain(split.toSavingsMinor);
    _bucketCtrl.text = _minorToPlain(split.toBucketMinor);
    _spendCtrl.text = _minorToPlain(split.toSpendMinor);
    _programmatic = false;
    setState(() => _rationale = split.rationale);
  }

  void _applySmartPreset() {
    final amt = _parseMinor(_amountCtrl.text);
    final gap = math.max<int>(0, -widget.snapshot.freeToSpendMinor);
    final bp = widget.snapshot.bucketPlan;
    final split = MonthlyTrackerEngine.suggestWindfallSplit(
      amountMinor: amt,
      monthGapMinor: gap,
      urgentShortfallMinor: bp.urgentShortfallMinor,
      essentialUnfundedMinor: bp.essentialUnfundedMinor,
      currencyCode: widget.currencyCode,
    );
    _applySplit(split);
  }

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final ccy = widget.currencyCode;

    final totalMinor = _parseMinor(_amountCtrl.text);
    final saveMinor = _parseMinor(_saveCtrl.text);
    final bucketMinor = _parseMinor(_bucketCtrl.text);
    final spendMinor = _parseMinor(_spendCtrl.text);
    final allocatedSum = saveMinor + bucketMinor + spendMinor;
    final isExact =
        totalMinor > 0 && allocatedSum == totalMinor && _accountId.isNotEmpty;

    final accOptions = [
      for (final a in widget.accounts)
        FintechDropdownOption(value: a.id, label: a.name),
    ];
    final goalOptions = <FintechDropdownOption<String>>[
      const FintechDropdownOption(
        value: _newFutureFundSentinel,
        label: 'Future Fund (Auto Goal)',
      ),
      for (final g in widget.goals)
        FintechDropdownOption(value: g.id, label: g.name),
    ];

    String fmt(int m) => Money(amountMinor: m, currencyCode: ccy).format();

    return ModernDialogShell(
      title: 'Add Extra Income',
      subtitle: 'Route windfalls deliberately across savings, bucket & spend',
      icon: Icons.savings_outlined,
      accent: ModernDialogAccent.success,
      confirmLabel: 'Record & Split',
      confirmKey: const Key('windfall_confirm_btn'),
      onConfirm: isExact
          ? () {
              Navigator.of(context).pop(
                WindfallDraft(
                  amountMinor: totalMinor,
                  sourceLabel: _sourceLabel,
                  accountId: _accountId,
                  goalId: _selectedGoalId == _newFutureFundSentinel
                      ? null
                      : _selectedGoalId,
                  split: WindfallSplit(
                    toSavingsMinor: saveMinor,
                    toBucketMinor: bucketMinor,
                    toSpendMinor: spendMinor,
                    rationale: _rationale,
                  ),
                ),
              );
            }
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FintechTextField(
            key: const Key('extra_income_amount_field'),
            label: 'Extra Income Amount ($ccy)',
            controller: _amountCtrl,
            compact: true,
            leadingIcon: Icons.add_card_rounded,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => _applySmartPreset(),
          ),
          const SizedBox(height: 10),
          Text(
            'Income Source',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final src in _sources)
                ChoiceChip(
                  label: Text(src),
                  selected: _sourceLabel == src,
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    setState(() => _sourceLabel = src);
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (accOptions.isNotEmpty)
            FintechDropdownField<String>(
              label: 'Deposit Into Account',
              value: _accountId,
              options: accOptions,
              leadingIcon: Icons.account_balance_outlined,
              compact: true,
              onChanged: (v) => setState(() => _accountId = v),
            ),
          const SizedBox(height: 12),
          Text(
            'Split Presets',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ActionChip(
                key: const Key('windfall_preset_smart'),
                avatar: Icon(
                  Icons.auto_awesome_rounded,
                  size: 15,
                  color: scheme.primary,
                ),
                label: const Text('Smart CFP'),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  _applySmartPreset();
                },
              ),
              ActionChip(
                label: const Text('50 / 30 / 20'),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  _applySplit(
                    MonthlyTrackerEngine.presetSplit(totalMinor, 50, 30),
                  );
                },
              ),
              ActionChip(
                label: const Text('Save All'),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  _applySplit(
                    MonthlyTrackerEngine.presetSplit(totalMinor, 100, 0),
                  );
                },
              ),
              ActionChip(
                label: const Text('Bucket First'),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  _applySplit(
                    MonthlyTrackerEngine.presetSplit(totalMinor, 30, 70),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: cfo.surfaceTonal,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: cfo.divider),
            ),
            child: Text(
              _rationale,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cfo.subtleText,
                height: 1.35,
              ),
            ),
          ),
          if (totalMinor > 0 && allocatedSum > 0) ...[
            const SizedBox(height: 10),
            SegmentedMoneyBar(
              height: 8,
              segments: [
                if (saveMinor > 0)
                  MoneyBarSegment(
                    label: 'Savings',
                    percent: saveMinor * 100.0 / math.max<int>(1, allocatedSum),
                    color: cfo.income,
                  ),
                if (bucketMinor > 0)
                  MoneyBarSegment(
                    label: 'Bucket',
                    percent:
                        bucketMinor * 100.0 / math.max<int>(1, allocatedSum),
                    color: scheme.primary,
                  ),
                if (spendMinor > 0)
                  MoneyBarSegment(
                    label: 'Month',
                    percent:
                        spendMinor * 100.0 / math.max<int>(1, allocatedSum),
                    color: cfo.warning,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          FintechTextField(
            label: 'Future Savings Goal ($ccy)',
            controller: _saveCtrl,
            compact: true,
            leadingIcon: Icons.savings_outlined,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) {
              if (!_programmatic) setState(() {});
            },
          ),
          const SizedBox(height: 8),
          FintechDropdownField<String>(
            label: 'Savings Goal Destination',
            value: _selectedGoalId,
            options: goalOptions,
            leadingIcon: Icons.flag_outlined,
            compact: true,
            onChanged: (v) => setState(() => _selectedGoalId = v),
          ),
          const SizedBox(height: 8),
          FintechTextField(
            label: 'Fund Bucket List Items ($ccy)',
            controller: _bucketCtrl,
            compact: true,
            leadingIcon: Icons.checklist_rounded,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) {
              if (!_programmatic) setState(() {});
            },
          ),
          const SizedBox(height: 8),
          FintechTextField(
            label: 'Add to This Month Spend Cap ($ccy)',
            controller: _spendCtrl,
            compact: true,
            leadingIcon: Icons.account_balance_wallet_outlined,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) {
              if (!_programmatic) setState(() {});
            },
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: (isExact ? cfo.incomeContainer : cfo.warningContainer)
                  .withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Row(
              children: [
                Icon(
                  isExact ? Icons.check_circle_outline : Icons.balance_rounded,
                  size: 16,
                  color: isExact ? cfo.income : cfo.warning,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Allocated ${fmt(allocatedSum)} of ${fmt(totalMinor)}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: isExact ? cfo.income : cfo.warning,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
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
