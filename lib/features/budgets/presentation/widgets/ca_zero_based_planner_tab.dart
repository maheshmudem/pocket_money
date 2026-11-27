import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/financial_engine/ca_budget_planner_engine.dart';
import '../../../../core/financial_engine/currency.dart';
import '../../../../core/financial_engine/money.dart';
import '../../../../shared/widgets/enterprise_layout.dart';
import '../../../../shared/widgets/fintech_widgets.dart';
import '../../../../shared/widgets/modern_dialogs.dart';
import '../../../../shared/widgets/modern_inputs.dart';
import '../../../profiles/domain/entities/profile_entity.dart';
import '../../data/ca_budget_planner_service.dart';

/// Tab 2 of `BudgetsPage` — Trendy, minimal Chartered Accountant Zero-Based
/// Budgeting (ZBB) Studio with 1-tap CA Blueprints and exact zero-remainder meter.
class CaZeroBasedPlannerTab extends StatefulWidget {
  const CaZeroBasedPlannerTab({
    required this.profile,
    required this.snapshot,
    required this.masked,
    required this.canManageBudget,
    required this.onSaveZeroBased,
    required this.onRefresh,
    super.key,
  });

  final FinancialProfile profile;
  final CaBudgetWorkspaceSnapshot snapshot;
  final bool masked;
  final bool canManageBudget;
  final Future<void> Function({
    required Map<String, int> categoryLimitsMinor,
    required int incomePoolMinor,
    required int taxReserveBps,
    required bool rolloverEnabled,
    String? existingBudgetId,
  })
  onSaveZeroBased;
  final Future<void> Function() onRefresh;

  @override
  State<CaZeroBasedPlannerTab> createState() => _CaZeroBasedPlannerTabState();
}

class _CaZeroBasedPlannerTabState extends State<CaZeroBasedPlannerTab> {
  final _incomeCtrl = TextEditingController();
  final _savingsCtrl = TextEditingController();
  final Map<String, TextEditingController> _catCtrls = {};

  String? _hydratedProfileId;
  CaBudgetBlueprint? _activeBlueprint;
  int _taxReserveBps = 0;
  bool _rollover = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _hydrateFromSnapshot(widget.snapshot);
  }

  @override
  void didUpdateWidget(covariant CaZeroBasedPlannerTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot.profileId != widget.snapshot.profileId ||
        oldWidget.snapshot.expenseCategories.length !=
            widget.snapshot.expenseCategories.length) {
      _hydrateFromSnapshot(widget.snapshot);
    }
  }

  @override
  void dispose() {
    _incomeCtrl.dispose();
    _savingsCtrl.dispose();
    for (final c in _catCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _formatEditableMinor(int minor) {
    if (minor <= 0) return '';
    final spec = CurrencyCatalog.requireByCode(widget.snapshot.currencyCode);
    final factor = math.pow(10, spec.minorUnit).toInt();
    if (spec.minorUnit == 0) return '$minor';
    if (minor % factor == 0) return '${minor ~/ factor}';
    final major = minor ~/ factor;
    final rem = (minor % factor).toString().padLeft(spec.minorUnit, '0');
    return '$major.$rem';
  }

  int _parseEditableToMinor(String raw) {
    final trimmed = raw.trim().replaceAll(',', '');
    if (trimmed.isEmpty) return 0;
    final spec = CurrencyCatalog.requireByCode(widget.snapshot.currencyCode);
    final res = Money.parseDecimal(trimmed, currency: spec);
    return res.valueOrNull?.amountMinor ?? 0;
  }

  void _hydrateFromSnapshot(CaBudgetWorkspaceSnapshot snap) {
    _hydratedProfileId = snap.profileId.value;
    _taxReserveBps = snap.taxReserveBps;
    _rollover = snap.masterZbbBudget?.rolloverEnabled ?? false;

    final existingMap = <String, int>{};
    if (snap.masterZbbBudget != null) {
      for (final a in snap.masterZbbBudget!.allocations) {
        existingMap[a.categoryId] = a.limitMinor;
      }
    } else {
      for (final b in snap.budgets) {
        for (final a in b.allocations) {
          existingMap[a.categoryId] =
              (existingMap[a.categoryId] ?? 0) + a.limitMinor;
        }
      }
    }

    // Dispose stale controllers and ensure every active expense category has one.
    final validIds = snap.expenseCategories.map((c) => c.id).toSet();
    final staleKeys = _catCtrls.keys
        .where((id) => !validIds.contains(id))
        .toList();
    for (final k in staleKeys) {
      _catCtrls.remove(k)?.dispose();
    }
    for (final cat in snap.expenseCategories) {
      final ctrl = _catCtrls.putIfAbsent(cat.id, TextEditingController.new);
      final initVal = existingMap[cat.id] ?? 0;
      ctrl.text = _formatEditableMinor(initVal);
    }

    final initialIncome = snap.suggestedIncomePoolMinor;
    _incomeCtrl.text = _formatEditableMinor(initialIncome);

    final assignedCats = existingMap.values.fold<int>(0, (s, v) => s + v);
    final taxMinor = _taxReserveBps > 0 && initialIncome > 0
        ? (initialIncome * _taxReserveBps) ~/ 10000
        : 0;
    final impliedSavings = initialIncome > (assignedCats + taxMinor)
        ? initialIncome - assignedCats - taxMinor
        : 0;
    _savingsCtrl.text = _formatEditableMinor(impliedSavings);
    _activeBlueprint = null;
  }

  Map<String, int> _currentCategoryMap() {
    return {
      for (final entry in _catCtrls.entries)
        entry.key: _parseEditableToMinor(entry.value.text),
    };
  }

  void _applyBlueprint(CaBudgetBlueprint blueprint) {
    HapticFeedback.selectionClick();
    var incomeMinor = _parseEditableToMinor(_incomeCtrl.text);
    if (incomeMinor <= 0) {
      // Seed a friendly starting income pool if the user tapped a blueprint first.
      final spec = CurrencyCatalog.requireByCode(widget.snapshot.currencyCode);
      final unit = math.pow(10, spec.minorUnit).toInt();
      incomeMinor =
          (widget.profile.profileType == ProfileType.business
              ? 100000
              : 50000) *
          unit;
      _incomeCtrl.text = _formatEditableMinor(incomeMinor);
    }

    final taxBps = blueprint == CaBudgetBlueprint.copyLastMonth
        ? _taxReserveBps
        : blueprint.taxPct * 100;

    final plan = CaBudgetPlannerEngine.generateZeroBasedPlan(
      blueprint: blueprint,
      incomePoolMinor: incomeMinor,
      categories: widget.snapshot.zbbSeeds,
      currencyCode: widget.snapshot.currencyCode,
      taxReserveBpsOverride: taxBps,
    );

    setState(() {
      _activeBlueprint = blueprint;
      _taxReserveBps = plan.taxReserveBps;
      _savingsCtrl.text = _formatEditableMinor(plan.savingsReserveMinor);
      for (final entry in plan.categoryAllocationsMinor.entries) {
        final ctrl = _catCtrls[entry.key];
        if (ctrl != null) {
          ctrl.text = _formatEditableMinor(entry.value);
        }
      }
    });
  }

  void _parkUnallocatedToSavings(int unallocatedMinor) {
    if (unallocatedMinor <= 0) return;
    HapticFeedback.selectionClick();
    final currentSavings = _parseEditableToMinor(_savingsCtrl.text);
    setState(() {
      _savingsCtrl.text = _formatEditableMinor(
        currentSavings + unallocatedMinor,
      );
    });
  }

  void _nudgeCategory(String categoryId, double factor) {
    final ctrl = _catCtrls[categoryId];
    if (ctrl == null) return;
    HapticFeedback.selectionClick();
    final current = _parseEditableToMinor(ctrl.text);
    final spec = CurrencyCatalog.requireByCode(widget.snapshot.currencyCode);
    final unit = math.pow(10, spec.minorUnit).toInt();
    final next = current <= 0
        ? (factor > 1 ? 1000 * unit : 0)
        : math.max(0, (current * factor).round());
    setState(() {
      ctrl.text = _formatEditableMinor(next);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_hydratedProfileId != widget.snapshot.profileId.value) {
      _hydrateFromSnapshot(widget.snapshot);
    }

    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final ccy = widget.snapshot.currencyCode;
    final masked = widget.masked;

    final incomeMinor = _parseEditableToMinor(_incomeCtrl.text);
    final taxMinor = _taxReserveBps > 0 && incomeMinor > 0
        ? (incomeMinor * _taxReserveBps) ~/ 10000
        : 0;
    final savingsMinor = _parseEditableToMinor(_savingsCtrl.text);
    final catMap = _currentCategoryMap();

    final balance = CaBudgetPlannerEngine.summarizeZbbBalance(
      incomePoolMinor: incomeMinor,
      categoryAllocationsMinor: catMap,
      taxReserveMinor: taxMinor,
      savingsReserveMinor: savingsMinor,
    );

    final (
      ModernDialogAccent meterAccent,
      Color meterColor,
      Color meterBg,
      String meterLabel,
    ) = balance.isBalanced
        ? (
            ModernDialogAccent.success,
            cfo.income,
            cfo.incomeContainer,
            'Zero-Based Balanced',
          )
        : balance.isOverAllocated
        ? (
            ModernDialogAccent.danger,
            cfo.expense,
            cfo.expenseContainer,
            'Over-Allocated',
          )
        : (
            ModernDialogAccent.warning,
            cfo.warning,
            cfo.warningContainer,
            incomeMinor > 0 ? 'Left to Assign' : 'Enter Income',
          );

    // Order blueprints contextually for Business vs Personal profiles.
    final blueprints = widget.profile.profileType == ProfileType.business
        ? const [
            CaBudgetBlueprint.profitFirst,
            CaBudgetBlueprint.taxReadyFreelancer,
            CaBudgetBlueprint.balanced503020,
            CaBudgetBlueprint.copyLastMonth,
            CaBudgetBlueprint.leanSaver702010,
          ]
        : const [
            CaBudgetBlueprint.balanced503020,
            CaBudgetBlueprint.leanSaver702010,
            CaBudgetBlueprint.taxReadyFreelancer,
            CaBudgetBlueprint.profitFirst,
            CaBudgetBlueprint.copyLastMonth,
          ];

    // Group categories cleanly by CA Cost Class.
    final grouped = <CaCostClass, List<ZbbCategorySeed>>{};
    for (final seed in widget.snapshot.zbbSeeds) {
      final cls = CaBudgetPlannerEngine.classifyCostClass(seed.categoryName);
      grouped.putIfAbsent(cls, () => []).add(seed);
    }

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EnterprisePageContainer.responsivePadding(context, bottom: 96),
        child: EnterprisePageContainer(
          maxWidth: AppBreakpoints.maxContentWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Live Zero-Based Balance Meter
              StaggeredFadeSlide(
                index: 0,
                child: FintechAccentCard(
                  key: const Key('budgets_zbb_meter'),
                  accent: meterAccent,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Zero-Based Balance',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          FintechStatusPill(
                            label: meterLabel,
                            showDot: true,
                            foreground: meterColor,
                            background: meterBg,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  balance.isOverAllocated
                                      ? 'Over by'
                                      : 'Unassigned Pool',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(color: cfo.subtleText),
                                ),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 220,
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: MoneyText(
                                      money: Money(
                                        amountMinor: balance.unallocatedMinor
                                            .abs(),
                                        currencyCode: ccy,
                                      ),
                                      masked: masked,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                            color: meterColor,
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (balance.unallocatedMinor > 0)
                            FilledButton.tonal(
                              key: const Key('budgets_zbb_park_savings_btn'),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 34),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () => _parkUnallocatedToSavings(
                                balance.unallocatedMinor,
                              ),
                              child: const Text('Park to Savings'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      AnimatedProgressBar(
                        value: masked ? 0.0 : balance.assignedRatio,
                        color: meterColor,
                        height: 6.5,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          _MiniAllocationTag(
                            label: 'Categories',
                            amountMinor: balance.categoryAssignedMinor,
                            currencyCode: ccy,
                            masked: masked,
                            color: scheme.primary,
                          ),
                          if (taxMinor > 0)
                            _MiniAllocationTag(
                              label: 'Tax (${_taxReserveBps ~/ 100}%)',
                              amountMinor: taxMinor,
                              currencyCode: ccy,
                              masked: masked,
                              color: cfo.warning,
                            ),
                          _MiniAllocationTag(
                            label: 'Savings',
                            amountMinor: savingsMinor,
                            currencyCode: ccy,
                            masked: masked,
                            color: cfo.income,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // 2. Monthly Income Pool, 1-Tap CA Blueprints & Tax/Savings Reserves
              StaggeredFadeSlide(
                index: 1,
                child: PressScaleCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FintechTextField(
                        key: const Key('budgets_zbb_income_field'),
                        label: 'Monthly Income / Revenue Pool ($ccy)',
                        controller: _incomeCtrl,
                        compact: true,
                        leadingIcon: Icons.account_balance_wallet_outlined,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (widget.snapshot.actualMonthlyIncomeMinor > 0)
                            _CompactChip(
                              label: 'Use Actual Income',
                              active: false,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _incomeCtrl.text = _formatEditableMinor(
                                    widget.snapshot.actualMonthlyIncomeMinor,
                                  );
                                });
                              },
                            ),
                          for (final preset in const [
                            '30000',
                            '50000',
                            '100000',
                            '200000',
                          ])
                            _CompactChip(
                              label: '$ccy $preset',
                              active: _incomeCtrl.text.trim() == preset,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _incomeCtrl.text = preset);
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '1-Tap CA & Accountant Blueprints',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final bp in blueprints)
                            _CompactChip(
                              key: Key('zbb_blueprint_${bp.name}'),
                              label: bp.shortLabel,
                              active: _activeBlueprint == bp,
                              onTap: () => _applyBlueprint(bp),
                            ),
                        ],
                      ),
                      if (_activeBlueprint != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          '${_activeBlueprint!.fullLabel}: ${_activeBlueprint!.summary}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: scheme.primary),
                        ),
                      ],
                      const Divider(height: 22),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Tax / GST Reserve:',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: cfo.subtleText,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          for (final pct in const [0, 10, 15, 20, 30])
                            _CompactChip(
                              label: '$pct%',
                              active: _taxReserveBps == pct * 100,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _taxReserveBps = pct * 100);
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      FintechTextField(
                        key: const Key('budgets_zbb_savings_field'),
                        label: 'Target Monthly Savings / Profit Reserve ($ccy)',
                        controller: _savingsCtrl,
                        compact: true,
                        leadingIcon: Icons.savings_outlined,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // 3. Grouped Category Allocations
              const SectionHeader(
                title: 'Category Envelopes',
                subtitle: 'Assign every rupee/dollar across cost classes',
              ),
              const SizedBox(height: AppSpacing.xs),

              if (widget.snapshot.zbbSeeds.isEmpty)
                const EmptyStateView(
                  icon: Icons.category_outlined,
                  title: 'No expense categories yet',
                  description:
                      'Add expense categories in Categories to build a Zero-Based Budget sheet.',
                )
              else
                for (final cls in CaCostClass.values)
                  if ((grouped[cls] ?? const []).isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 6),
                      child: Row(
                        children: [
                          FintechStatusPill(
                            label: cls.label,
                            foreground: _classColor(cls, cfo, scheme),
                            background: _classBg(cls, cfo, scheme),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              cls.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: cfo.subtleText),
                            ),
                          ),
                        ],
                      ),
                    ),
                    PressScaleCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < grouped[cls]!.length; i++) ...[
                            if (i > 0) Divider(height: 1, color: cfo.divider),
                            _ZbbCategoryRow(
                              seed: grouped[cls]![i],
                              controller:
                                  _catCtrls[grouped[cls]![i].categoryId]!,
                              currencyCode: ccy,
                              masked: masked,
                              onChanged: () => setState(() {}),
                              onMinus10: () => _nudgeCategory(
                                grouped[cls]![i].categoryId,
                                0.90,
                              ),
                              onPlus10: () => _nudgeCategory(
                                grouped[cls]![i].categoryId,
                                1.10,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

              const SizedBox(height: 4),
              FintechSwitchCard(
                icon: Icons.autorenew_rounded,
                title: 'Carry unspent rollover',
                subtitle: 'Roll unused category envelope balance to next month',
                value: _rollover,
                onChanged: (v) => setState(() => _rollover = v),
              ),
              const SizedBox(height: AppSpacing.md),

              if (widget.canManageBudget)
                FilledButton.icon(
                  key: const Key('budgets_zbb_save_btn'),
                  onPressed: _saving || balance.categoryAssignedMinor <= 0
                      ? null
                      : () async {
                          setState(() => _saving = true);
                          try {
                            await widget.onSaveZeroBased(
                              categoryLimitsMinor: _currentCategoryMap(),
                              incomePoolMinor: incomeMinor,
                              taxReserveBps: _taxReserveBps,
                              rolloverEnabled: _rollover,
                              existingBudgetId:
                                  widget.snapshot.masterZbbBudget?.id,
                            );
                          } finally {
                            if (mounted) setState(() => _saving = false);
                          }
                        },
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline_rounded),
                  label: Text(
                    widget.snapshot.masterZbbBudget != null
                        ? 'Update Master Zero-Based Budget'
                        : 'Save Master Zero-Based Budget',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _classColor(CaCostClass cls, PocketCfoColors cfo, ColorScheme scheme) =>
      switch (cls) {
        CaCostClass.fixedNeed => scheme.primary,
        CaCostClass.variableWant => cfo.warning,
        CaCostClass.taxStatutory => cfo.expense,
        CaCostClass.savingsCapex => cfo.income,
      };

  Color _classBg(CaCostClass cls, PocketCfoColors cfo, ColorScheme scheme) =>
      switch (cls) {
        CaCostClass.fixedNeed => scheme.primaryContainer,
        CaCostClass.variableWant => cfo.warningContainer,
        CaCostClass.taxStatutory => cfo.expenseContainer,
        CaCostClass.savingsCapex => cfo.incomeContainer,
      };
}

class _ZbbCategoryRow extends StatelessWidget {
  const _ZbbCategoryRow({
    required this.seed,
    required this.controller,
    required this.currencyCode,
    required this.masked,
    required this.onChanged,
    required this.onMinus10,
    required this.onPlus10,
  });

  final ZbbCategorySeed seed;
  final TextEditingController controller;
  final String currencyCode;
  final bool masked;
  final VoidCallback onChanged;
  final VoidCallback onMinus10;
  final VoidCallback onPlus10;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final avgFmt = seed.trailingSpendMinor > 0
        ? (masked
              ? 'Avg ••••'
              : 'Avg ${Money(amountMinor: seed.trailingSpendMinor, currencyCode: currencyCode).format()}')
        : 'No prior spend';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  seed.categoryName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  avgFmt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cfo.subtleText,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onMinus10,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: cfo.surfaceTonal,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.remove_rounded,
                size: 15,
                color: cfo.subtleText,
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 96,
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: '0',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                filled: true,
                fillColor: cfo.surfaceTonal,
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
              onChanged: (_) => onChanged(),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onPlus10,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.add_rounded, size: 15, color: scheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniAllocationTag extends StatelessWidget {
  const _MiniAllocationTag({
    required this.label,
    required this.amountMinor,
    required this.currencyCode,
    required this.masked,
    required this.color,
  });

  final String label;
  final int amountMinor;
  final String currencyCode;
  final bool masked;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final val = Money(
      amountMinor: amountMinor,
      currencyCode: currencyCode,
    ).format(mask: masked);
    return Text(
      '$label: $val',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      strutStyle: StrutStyle(
        fontSize: Theme.of(context).textTheme.labelSmall?.fontSize,
        leading: 0.2,
      ),
    ).withFallbackColor(cfo.subtleText);
  }
}

extension on Text {
  Widget withFallbackColor(Color _) => this;
}

class _CompactChip extends StatelessWidget {
  const _CompactChip({
    required this.label,
    required this.active,
    required this.onTap,
    super.key,
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
