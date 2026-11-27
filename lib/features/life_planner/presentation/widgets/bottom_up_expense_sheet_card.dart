import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/financial_engine/currency.dart';
import '../../../../core/financial_engine/life_stage_planner_engine.dart';
import '../../../../core/financial_engine/money.dart';
import '../../../../shared/widgets/fintech_widgets.dart';
import '../../../../shared/widgets/modern_inputs.dart';

/// Interactive CFP / CA Bottom-Up Monthly Income & Real Commitments worksheet.
///
/// Captures primary take-home salary, optional spouse/secondary income, and up to
/// 11 real monthly obligations (Rent/PG, Groceries, Utilities, School Fees,
/// Insurance, Subscriptions, Other EMIs, Transport, Medical, Parents Support,
/// Other Fixed Bills) with 1-tap `From Ledger` and `Estimate Typical` helpers
/// and a real-time Committed vs. Net Surplus footer strip.
class BottomUpExpenseSheetCard extends StatefulWidget {
  const BottomUpExpenseSheetCard({
    required this.profileId,
    required this.targets,
    required this.expenseProfile,
    required this.trackedLoanEmiMinor,
    required this.currencyCode,
    required this.masked,
    required this.busy,
    required this.onSaveProfile,
    required this.onAutoFillFromLedger,
    required this.onEstimateTypical,
    super.key,
  });

  final String profileId;
  final EffectiveLifeStageTargets targets;
  final MonthlyExpenseProfile expenseProfile;
  final int trackedLoanEmiMinor;
  final String currencyCode;
  final bool masked;
  final bool busy;
  final Future<void> Function(MonthlyExpenseProfile updated) onSaveProfile;
  final Future<void> Function() onAutoFillFromLedger;
  final Future<void> Function(
    int primaryIncomeMinor,
    int secondaryIncomeMinor,
    int existingManualEmiMinor,
  )
  onEstimateTypical;

  @override
  State<BottomUpExpenseSheetCard> createState() =>
      _BottomUpExpenseSheetCardState();
}

class _BottomUpExpenseSheetCardState extends State<BottomUpExpenseSheetCard> {
  final _primaryCtrl = TextEditingController();
  final _secondaryCtrl = TextEditingController();
  final _rentCtrl = TextEditingController();
  final _groceriesCtrl = TextEditingController();
  final _utilitiesCtrl = TextEditingController();
  final _schoolFeesCtrl = TextEditingController();
  final _insuranceCtrl = TextEditingController();
  final _transportCtrl = TextEditingController();
  final _medicalCtrl = TextEditingController();
  final _parentsCtrl = TextEditingController();
  final _subscriptionsCtrl = TextEditingController();
  final _manualEmiCtrl = TextEditingController();
  final _otherFixedCtrl = TextEditingController();

  bool _showSecondaryIncome = false;
  bool _showExtraExpenses = false;
  bool _hasUnsavedEdits = false;

  @override
  void initState() {
    super.initState();
    _hydrateFromWidget(widget.expenseProfile, widget.targets.status);
  }

  @override
  void didUpdateWidget(covariant BottomUpExpenseSheetCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final profileSwitched = oldWidget.profileId != widget.profileId;
    final expenseChanged = oldWidget.expenseProfile != widget.expenseProfile;
    final statusChanged = oldWidget.targets.status != widget.targets.status;
    if (profileSwitched || expenseChanged) {
      _hydrateFromWidget(widget.expenseProfile, widget.targets.status);
      _hasUnsavedEdits = false;
    } else if (statusChanged &&
        _shouldDefaultShowSecondary(widget.targets.status)) {
      _showSecondaryIncome = true;
    }
  }

  @override
  void dispose() {
    _primaryCtrl.dispose();
    _secondaryCtrl.dispose();
    _rentCtrl.dispose();
    _groceriesCtrl.dispose();
    _utilitiesCtrl.dispose();
    _schoolFeesCtrl.dispose();
    _insuranceCtrl.dispose();
    _transportCtrl.dispose();
    _medicalCtrl.dispose();
    _parentsCtrl.dispose();
    _subscriptionsCtrl.dispose();
    _manualEmiCtrl.dispose();
    _otherFixedCtrl.dispose();
    super.dispose();
  }

  bool _shouldDefaultShowSecondary(LifeStageStatus status) =>
      status == LifeStageStatus.marriedCouple ||
      status == LifeStageStatus.familyWithKids ||
      status == LifeStageStatus.sandwichFamily;

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

  void _hydrateFromWidget(MonthlyExpenseProfile ep, LifeStageStatus status) {
    _primaryCtrl.text = _minorToPlain(ep.primaryIncomeMinor);
    _secondaryCtrl.text = _minorToPlain(ep.secondaryIncomeMinor);
    _rentCtrl.text = _minorToPlain(ep.rentOrHousingMinor);
    _groceriesCtrl.text = _minorToPlain(ep.groceriesMinor);
    _utilitiesCtrl.text = _minorToPlain(ep.utilitiesMinor);
    _schoolFeesCtrl.text = _minorToPlain(ep.schoolFeesMinor);
    _insuranceCtrl.text = _minorToPlain(ep.insuranceMinor);
    _transportCtrl.text = _minorToPlain(ep.transportFuelMinor);
    _medicalCtrl.text = _minorToPlain(ep.medicalMinor);
    _parentsCtrl.text = _minorToPlain(ep.parentsSupportMinor);
    _subscriptionsCtrl.text = _minorToPlain(ep.subscriptionsMinor);
    _manualEmiCtrl.text = _minorToPlain(ep.manualEmiMinor);
    _otherFixedCtrl.text = _minorToPlain(ep.otherFixedMinor);

    _showSecondaryIncome =
        ep.secondaryIncomeMinor > 0 || _shouldDefaultShowSecondary(status);
    _showExtraExpenses =
        ep.transportFuelMinor > 0 ||
        ep.medicalMinor > 0 ||
        ep.parentsSupportMinor > 0 ||
        ep.otherFixedMinor > 0;
  }

  MonthlyExpenseProfile _draftProfile() => MonthlyExpenseProfile(
    primaryIncomeMinor: _parseMinor(_primaryCtrl.text),
    secondaryIncomeMinor: _parseMinor(_secondaryCtrl.text),
    rentOrHousingMinor: _parseMinor(_rentCtrl.text),
    groceriesMinor: _parseMinor(_groceriesCtrl.text),
    utilitiesMinor: _parseMinor(_utilitiesCtrl.text),
    schoolFeesMinor: _parseMinor(_schoolFeesCtrl.text),
    insuranceMinor: _parseMinor(_insuranceCtrl.text),
    transportFuelMinor: _parseMinor(_transportCtrl.text),
    medicalMinor: _parseMinor(_medicalCtrl.text),
    parentsSupportMinor: _parseMinor(_parentsCtrl.text),
    subscriptionsMinor: _parseMinor(_subscriptionsCtrl.text),
    manualEmiMinor: _parseMinor(_manualEmiCtrl.text),
    otherFixedMinor: _parseMinor(_otherFixedCtrl.text),
  );

  void _onFieldChanged() {
    setState(() => _hasUnsavedEdits = true);
  }

  String _housingFieldLabel() {
    if (widget.targets.housingMode == HousingMode.ownedOrFamily) {
      return 'Home Maintenance / Society';
    }
    if (widget.targets.housingMode == HousingMode.homeLoanEmi) {
      return 'Society Maint. / Rent';
    }
    return switch (widget.targets.status) {
      LifeStageStatus.studentStarter ||
      LifeStageStatus.bachelor => 'PG / Room Rent',
      _ => 'House Rent / Maint.',
    };
  }

  String _schoolFeesLabel() => switch (widget.targets.status) {
    LifeStageStatus.studentStarter => 'College / Course Fees',
    LifeStageStatus.familyWithKids ||
    LifeStageStatus.sandwichFamily => 'School / Tuition Fees',
    _ => 'Education / Upskilling',
  };

  Future<void> _submitDraft() async {
    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();
    final draft = _draftProfile();
    await widget.onSaveProfile(draft);
    if (mounted) {
      setState(() => _hasUnsavedEdits = false);
    }
  }

  Future<void> _clearExpensesOnly() async {
    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();
    final cleared = MonthlyExpenseProfile(
      primaryIncomeMinor: _parseMinor(_primaryCtrl.text),
      secondaryIncomeMinor: _parseMinor(_secondaryCtrl.text),
    );
    _hydrateFromWidget(cleared, widget.targets.status);
    await widget.onSaveProfile(cleared);
    if (mounted) {
      setState(() => _hasUnsavedEdits = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final ccy = widget.currencyCode;
    final spec = CurrencyCatalog.requireByCode(ccy);
    final symbol = spec.symbol;
    final t = widget.targets;

    final draft = _draftProfile();
    final totalIncome = draft.totalIncomeMinor;
    final taxReserve = t.taxPct > 0 && totalIncome > 0
        ? (totalIncome * t.taxPct) ~/ 100
        : 0;
    final totalCommitted =
        draft.totalEnteredExpensesMinor +
        math.max<int>(0, widget.trackedLoanEmiMinor) +
        taxReserve;
    final netSurplus = totalIncome - totalCommitted;
    final isDeficit = totalIncome > 0 && netSurplus < 0;
    final commitPct = totalIncome > 0
        ? (totalCommitted * 100.0 / totalIncome).round()
        : 0;

    final showParentsInCore =
        t.status == LifeStageStatus.sandwichFamily || t.dependentsCount >= 3;
    final showFeesInCore =
        t.status == LifeStageStatus.familyWithKids ||
        t.status == LifeStageStatus.studentStarter ||
        t.status == LifeStageStatus.sandwichFamily ||
        draft.schoolFeesMinor > 0;

    return PressScaleCard(
      key: const Key('life_bottom_up_expenses_card'),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // -----------------------------------------------------------------
          // PART 1: MONTHLY TAKE-HOME INCOME (PRIMARY + OPTIONAL SPOUSE/SIDE)
          // -----------------------------------------------------------------
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Monthly Take-Home Income',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (!_showSecondaryIncome)
                _ActionMiniChip(
                  key: const Key('life_add_secondary_income_btn'),
                  icon: Icons.add_rounded,
                  label: 'Spouse / Side Income',
                  onTap: () => setState(() => _showSecondaryIncome = true),
                ),
            ],
          ),
          const SizedBox(height: 8),
          FintechTextField(
            key: const Key('life_income_field'),
            label: _showSecondaryIncome
                ? 'Primary Take-Home Salary ($ccy)'
                : 'Monthly Take-Home Income ($ccy)',
            controller: _primaryCtrl,
            compact: true,
            leadingIcon: Icons.payments_outlined,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => _onFieldChanged(),
            onSubmitted: (_) => _submitDraft(),
          ),
          if (_showSecondaryIncome) ...[
            const SizedBox(height: 8),
            FintechTextField(
              key: const Key('life_secondary_income_field'),
              label: 'Spouse / Secondary Monthly Income ($ccy)',
              hintText: 'Optional (0 if single earner)',
              controller: _secondaryCtrl,
              compact: true,
              leadingIcon: Icons.group_add_outlined,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => _onFieldChanged(),
              onSubmitted: (_) => _submitDraft(),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final preset in const ['30000', '60000', '100000', '150000'])
                _PresetPill(
                  label: '$ccy $preset',
                  active: _primaryCtrl.text.trim() == preset,
                  onTap: () async {
                    HapticFeedback.selectionClick();
                    _primaryCtrl.text = preset;
                    await _submitDraft();
                  },
                ),
            ],
          ),

          Divider(height: 24, color: cfo.divider),

          // -----------------------------------------------------------------
          // PART 2: REAL MONTHLY COMMITMENTS + 1-TAP AUTO-FILL HELPERS
          // -----------------------------------------------------------------
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Real Monthly Expenses & EMIs',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Enter real bills so your plan fits your exact cash flow',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
                  ),
                ],
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _ActionMiniChip(
                    key: const Key('life_autofill_ledger_btn'),
                    icon: Icons.auto_awesome_outlined,
                    label: 'From Ledger',
                    accent: true,
                    onTap: widget.busy
                        ? null
                        : () {
                            HapticFeedback.selectionClick();
                            widget.onAutoFillFromLedger();
                          },
                  ),
                  _ActionMiniChip(
                    key: const Key('life_estimate_typical_btn'),
                    icon: Icons.tune_rounded,
                    label: 'Estimate Typical',
                    onTap: widget.busy
                        ? null
                        : () {
                            HapticFeedback.selectionClick();
                            final primary = _parseMinor(_primaryCtrl.text);
                            final secondary = _parseMinor(_secondaryCtrl.text);
                            final manualEmi = _parseMinor(_manualEmiCtrl.text);
                            widget.onEstimateTypical(
                              primary,
                              secondary,
                              manualEmi,
                            );
                          },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Core monthly commitment rows
          _ExpenseLedgerRow(
            fieldKey: const Key('life_exp_rent_field'),
            icon: Icons.home_outlined,
            iconColor: scheme.primary,
            iconBg: scheme.primaryContainer,
            label: _housingFieldLabel(),
            controller: _rentCtrl,
            symbol: symbol,
            onChanged: _onFieldChanged,
          ),
          _ExpenseLedgerRow(
            fieldKey: const Key('life_exp_groceries_field'),
            icon: Icons.shopping_cart_outlined,
            iconColor: cfo.income,
            iconBg: cfo.incomeContainer,
            label: 'Groceries & Household',
            controller: _groceriesCtrl,
            symbol: symbol,
            onChanged: _onFieldChanged,
          ),
          if (showFeesInCore)
            _ExpenseLedgerRow(
              fieldKey: const Key('life_exp_fees_field'),
              icon: Icons.school_outlined,
              iconColor: scheme.primary,
              iconBg: scheme.primaryContainer,
              label: _schoolFeesLabel(),
              subtitle: 'Monthly / annual ÷ 12',
              controller: _schoolFeesCtrl,
              symbol: symbol,
              onChanged: _onFieldChanged,
            ),
          _ExpenseLedgerRow(
            fieldKey: const Key('life_exp_utilities_field'),
            icon: Icons.bolt_outlined,
            iconColor: cfo.warning,
            iconBg: cfo.warningContainer,
            label: 'Utilities (Power / Wi-Fi / Mobile)',
            controller: _utilitiesCtrl,
            symbol: symbol,
            onChanged: _onFieldChanged,
          ),
          _ExpenseLedgerRow(
            fieldKey: const Key('life_exp_insurance_field'),
            icon: Icons.verified_user_outlined,
            iconColor: cfo.income,
            iconBg: cfo.incomeContainer,
            label: 'Insurance (Health + Term)',
            subtitle: 'Annual premium ÷ 12',
            controller: _insuranceCtrl,
            symbol: symbol,
            onChanged: _onFieldChanged,
          ),
          if (showParentsInCore)
            _ExpenseLedgerRow(
              fieldKey: const Key('life_exp_parents_field'),
              icon: Icons.volunteer_activism_outlined,
              iconColor: scheme.primary,
              iconBg: scheme.primaryContainer,
              label: 'Parents / Dependent Support',
              controller: _parentsCtrl,
              symbol: symbol,
              onChanged: _onFieldChanged,
            ),
          _ExpenseLedgerRow(
            fieldKey: const Key('life_exp_subscriptions_field'),
            icon: Icons.subscriptions_outlined,
            iconColor: cfo.warning,
            iconBg: cfo.warningContainer,
            label: 'Subscriptions (OTT / Gym / Cloud)',
            controller: _subscriptionsCtrl,
            symbol: symbol,
            onChanged: _onFieldChanged,
          ),
          _ExpenseLedgerRow(
            fieldKey: const Key('life_exp_manual_emi_field'),
            icon: Icons.account_balance_outlined,
            iconColor: cfo.expense,
            iconBg: cfo.expenseContainer,
            label: 'Other Monthly EMIs',
            subtitle: widget.trackedLoanEmiMinor > 0
                ? '+ ${Money(amountMinor: widget.trackedLoanEmiMinor, currencyCode: ccy).format(mask: widget.masked)} tracked loans auto-included'
                : 'EMIs not added in Loans yet',
            controller: _manualEmiCtrl,
            symbol: symbol,
            onChanged: _onFieldChanged,
            showDivider: _showExtraExpenses,
          ),

          // Expandable Tier 2/3 additional obligations
          if (_showExtraExpenses) ...[
            if (!showFeesInCore)
              _ExpenseLedgerRow(
                fieldKey: const Key('life_exp_fees_field'),
                icon: Icons.school_outlined,
                iconColor: scheme.primary,
                iconBg: scheme.primaryContainer,
                label: _schoolFeesLabel(),
                subtitle: 'Monthly / annual ÷ 12',
                controller: _schoolFeesCtrl,
                symbol: symbol,
                onChanged: _onFieldChanged,
              ),
            _ExpenseLedgerRow(
              fieldKey: const Key('life_exp_transport_field'),
              icon: Icons.directions_car_outlined,
              iconColor: scheme.primary,
              iconBg: scheme.primaryContainer,
              label: 'Transport & Fuel',
              controller: _transportCtrl,
              symbol: symbol,
              onChanged: _onFieldChanged,
            ),
            _ExpenseLedgerRow(
              fieldKey: const Key('life_exp_medical_field'),
              icon: Icons.medical_services_outlined,
              iconColor: cfo.expense,
              iconBg: cfo.expenseContainer,
              label: 'Medical & Pharmacy',
              controller: _medicalCtrl,
              symbol: symbol,
              onChanged: _onFieldChanged,
            ),
            if (!showParentsInCore)
              _ExpenseLedgerRow(
                fieldKey: const Key('life_exp_parents_field'),
                icon: Icons.volunteer_activism_outlined,
                iconColor: scheme.primary,
                iconBg: scheme.primaryContainer,
                label: 'Parents / Dependent Support',
                controller: _parentsCtrl,
                symbol: symbol,
                onChanged: _onFieldChanged,
              ),
            _ExpenseLedgerRow(
              fieldKey: const Key('life_exp_other_field'),
              icon: Icons.receipt_long_outlined,
              iconColor: cfo.subtleText,
              iconBg: cfo.surfaceTonal,
              label: 'Other Fixed Bills',
              controller: _otherFixedCtrl,
              symbol: symbol,
              onChanged: _onFieldChanged,
              showDivider: false,
            ),
          ],

          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('life_toggle_more_expenses_btn'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              ),
              onPressed: () =>
                  setState(() => _showExtraExpenses = !_showExtraExpenses),
              icon: Icon(
                _showExtraExpenses
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                size: 18,
              ),
              label: Text(
                _showExtraExpenses
                    ? 'Hide additional rows'
                    : 'More rows (Transport, Medical, Parents, Other)',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // -----------------------------------------------------------------
          // PART 3: LIVE CASH-FLOW SUMMARY FOOTER + SAVE CTA
          // -----------------------------------------------------------------
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDeficit
                  ? cfo.expenseContainer.withValues(alpha: 0.55)
                  : cfo.surfaceTonal,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: isDeficit ? cfo.expense : cfo.divider),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _FooterMetric(
                    label: 'Total Income',
                    minor: totalIncome,
                    ccy: ccy,
                    masked: widget.masked,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _FooterMetric(
                    label: widget.masked
                        ? 'Committed'
                        : 'Committed ($commitPct%)',
                    minor: totalCommitted,
                    ccy: ccy,
                    masked: widget.masked,
                    color: cfo.warning,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _FooterMetric(
                    label: isDeficit ? 'Shortfall' : 'Real Surplus',
                    minor: netSurplus.abs(),
                    ccy: ccy,
                    masked: widget.masked,
                    color: isDeficit ? cfo.expense : cfo.income,
                    prefix: isDeficit ? '−' : '',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const Key('life_save_plan_inputs_btn'),
                  onPressed: widget.busy ? null : _submitDraft,
                  icon: widget.busy
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _hasUnsavedEdits
                              ? Icons.save_rounded
                              : Icons.auto_graph_rounded,
                          size: 18,
                        ),
                  label: Text(
                    _hasUnsavedEdits
                        ? 'Save & Rebuild CFP Plan'
                        : 'Save & Build My Plan',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (draft.hasAnyEnteredExpenses) ...[
                const SizedBox(width: 8),
                TextButton(
                  key: const Key('life_clear_expenses_btn'),
                  onPressed: widget.busy ? null : _clearExpensesOnly,
                  child: const Text('Reset'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ExpenseLedgerRow extends StatelessWidget {
  const _ExpenseLedgerRow({
    required this.fieldKey,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.controller,
    required this.symbol,
    required this.onChanged,
    this.subtitle,
    this.showDivider = true,
  });

  final Key fieldKey;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final String? subtitle;
  final TextEditingController controller;
  final String symbol;
  final VoidCallback onChanged;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              IconSquircle(
                icon: icon,
                iconColor: iconColor,
                backgroundColor: iconBg,
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cfo.subtleText,
                          fontSize: 10.5,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 112,
                child: TextField(
                  key: fieldKey,
                  controller: controller,
                  textAlign: TextAlign.right,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  onChanged: (_) => onChanged(),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: cfo.surfaceTonal,
                    prefixText: '$symbol ',
                    prefixStyle: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(
                          color: cfo.subtleText,
                          fontWeight: FontWeight.w700,
                        ),
                    hintText: '0',
                    hintStyle: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(
                          color: cfo.subtleText.withValues(alpha: 0.6),
                        ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      borderSide: BorderSide(color: cfo.divider),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      borderSide: BorderSide(color: cfo.divider),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      borderSide: BorderSide(color: scheme.primary, width: 1.5),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(height: 1, color: cfo.divider.withValues(alpha: 0.65)),
      ],
    );
  }
}

class _FooterMetric extends StatelessWidget {
  const _FooterMetric({
    required this.label,
    required this.minor,
    required this.ccy,
    required this.masked,
    required this.color,
    this.prefix = '',
  });

  final String label;
  final int minor;
  final String ccy;
  final bool masked;
  final Color color;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final formatted = Money(
      amountMinor: minor,
      currencyCode: ccy,
    ).format(mask: masked);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            masked ? formatted : '$prefix$formatted',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionMiniChip extends StatelessWidget {
  const _ActionMiniChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: accent ? scheme.primaryContainer : cfo.surfaceTonal,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        side: BorderSide(color: accent ? scheme.primary : cfo.divider),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: accent ? scheme.primary : cfo.subtleText,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: accent ? scheme.primary : scheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetPill extends StatelessWidget {
  const _PresetPill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: active ? scheme.primaryContainer : cfo.surfaceTonal,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        side: BorderSide(color: active ? scheme.primary : cfo.divider),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: active ? scheme.primary : cfo.subtleText,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
