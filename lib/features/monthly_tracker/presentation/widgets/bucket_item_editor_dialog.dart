import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/financial_engine/currency.dart';
import '../../../../core/financial_engine/money.dart';
import '../../../../core/financial_engine/monthly_tracker_engine.dart';
import '../../../../shared/widgets/modern_dialogs.dart';
import '../../../../shared/widgets/modern_dropdown.dart';
import '../../../../shared/widgets/modern_inputs.dart';
import '../../../categories/domain/entities/category_entity.dart';
import '../../domain/entities/bucket_list_item_entity.dart';

/// Result returned when the user saves an item from [BucketItemEditorDialog].
final class BucketItemDraft {
  const BucketItemDraft({
    required this.name,
    required this.estimatedAmountMinor,
    required this.priority,
    required this.targetYearMonth,
    this.dueDateUtc,
    this.reminderAtUtc,
    this.categoryId,
    this.note,
  });

  final String name;
  final int estimatedAmountMinor;
  final BucketPriority priority;
  final String targetYearMonth;
  final String? dueDateUtc;
  final String? reminderAtUtc;
  final String? categoryId;
  final String? note;
}

/// Interactive create / edit modal for Monthly Bucket List items.
class BucketItemEditorDialog extends StatefulWidget {
  const BucketItemEditorDialog({
    required this.currencyCode,
    required this.baseYear,
    required this.baseMonth,
    required this.expenseCategories,
    this.existing,
    this.snapshot,
    super.key,
  });

  final String currencyCode;
  final int baseYear;
  final int baseMonth;
  final List<CategoryEntity> expenseCategories;
  final BucketListItemEntity? existing;
  final MonthlyTrackerSnapshot? snapshot;

  @override
  State<BucketItemEditorDialog> createState() => _BucketItemEditorDialogState();
}

class _BucketItemEditorDialogState extends State<BucketItemEditorDialog> {
  static const _noCatSentinel = '__none__';
  static const _templates = [
    (
      label: 'Repair',
      name: 'Home / Vehicle Repair',
      priority: BucketPriority.urgent,
    ),
    (
      label: 'Health',
      name: 'Medical / Wellness',
      priority: BucketPriority.essential,
    ),
    (label: 'Gadget', name: 'Tech Upgrade', priority: BucketPriority.nice),
    (
      label: 'Clothing',
      name: 'Wardrobe Essential',
      priority: BucketPriority.nice,
    ),
    (label: 'Home', name: 'Home Appliance', priority: BucketPriority.essential),
    (label: 'Travel', name: 'Dream Trip', priority: BucketPriority.dream),
  ];

  late final TextEditingController _nameCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _noteCtrl;

  late BucketPriority _priority;
  late String _targetMonthKey;
  DateTime? _dueDateLocal;
  bool _reminderEnabled = false;
  String? _categoryId;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _nameCtrl = TextEditingController(text: ex?.name ?? '');
    _amountCtrl = TextEditingController(
      text: ex != null ? _minorToPlain(ex.estimatedAmountMinor) : '',
    );
    _noteCtrl = TextEditingController(text: ex?.note ?? '');
    _priority = ex?.priority ?? BucketPriority.essential;
    _targetMonthKey =
        ex?.targetYearMonth ??
        MonthlyTrackerEngine.monthKey(widget.baseYear, widget.baseMonth);
    _dueDateLocal = ex?.dueDateUtc != null
        ? DateTime.tryParse(ex!.dueDateUtc!)?.toLocal()
        : null;
    _reminderEnabled = ex?.reminderAtUtc != null;
    _categoryId = ex?.categoryId;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
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

  String _defaultReminderIsoUtc() {
    final nowLocal = DateTime.now();
    final anchor = _dueDateLocal != null
        ? _dueDateLocal!.subtract(const Duration(days: 1))
        : nowLocal.add(const Duration(days: 1));
    var localMorning = DateTime(anchor.year, anchor.month, anchor.day, 9, 0);
    if (!localMorning.isAfter(nowLocal)) {
      final tmrw = nowLocal.add(const Duration(days: 1));
      localMorning = DateTime(tmrw.year, tmrw.month, tmrw.day, 9, 0);
    }
    return localMorning.toUtc().toIso8601String();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    final amountMinor = _parseMinor(_amountCtrl.text);
    if (name.isEmpty) {
      setState(() => _errorText = 'Enter an item name.');
      return;
    }
    if (amountMinor <= 0) {
      setState(() => _errorText = 'Enter a valid estimated price.');
      return;
    }

    final dueUtc = _dueDateLocal != null
        ? DateTime.utc(
            _dueDateLocal!.year,
            _dueDateLocal!.month,
            _dueDateLocal!.day,
            12,
          ).toIso8601String()
        : null;
    final reminderUtc = _reminderEnabled ? _defaultReminderIsoUtc() : null;

    Navigator.of(context).pop(
      BucketItemDraft(
        name: name,
        estimatedAmountMinor: amountMinor,
        priority: _priority,
        targetYearMonth: _targetMonthKey,
        dueDateUtc: dueUtc,
        reminderAtUtc: reminderUtc,
        categoryId: _categoryId,
        note: _noteCtrl.text.trim().isNotEmpty ? _noteCtrl.text.trim() : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final baseKey = MonthlyTrackerEngine.monthKey(
      widget.baseYear,
      widget.baseMonth,
    );
    final nextKey = MonthlyTrackerEngine.shiftMonth(baseKey, 1);
    final plus2Key = MonthlyTrackerEngine.shiftMonth(baseKey, 2);

    String monthChipLabel(String key) {
      final (y, m) = MonthlyTrackerEngine.parseMonthKey(key);
      return DateFormat('MMM yyyy').format(DateTime.utc(y, m, 1));
    }

    final catOptions = <FintechDropdownOption<String>>[
      const FintechDropdownOption(
        value: _noCatSentinel,
        label: 'No Category (Assign Later)',
      ),
      for (final c in widget.expenseCategories)
        FintechDropdownOption(value: c.id, label: c.name),
    ];

    final liveAmountMinor = _parseMinor(_amountCtrl.text);
    final preview =
        widget.snapshot != null &&
            (liveAmountMinor > 0 || _priority == BucketPriority.dream)
        ? MonthlyTrackerEngine.previewPurchaseAffordability(
            snapshot: widget.snapshot!,
            amountMinor: liveAmountMinor,
            priority: _priority.wireValue,
          )
        : null;
    final (
      Color prevFg,
      Color prevBg,
      IconData prevIcon,
    ) = switch (preview?.tone) {
      'safe' => (
        cfo.income,
        cfo.incomeContainer,
        Icons.check_circle_outline_rounded,
      ),
      'caution' => (
        cfo.warning,
        cfo.warningContainer,
        Icons.hourglass_bottom_rounded,
      ),
      'tight' => (
        cfo.expense,
        cfo.expenseContainer,
        Icons.warning_amber_rounded,
      ),
      _ => (scheme.primary, scheme.primaryContainer, Icons.flag_outlined),
    };

    return ModernDialogShell(
      title: widget.existing == null
          ? 'Add to Bucket List'
          : 'Edit Bucket Item',
      subtitle: 'Plan purchases against your real monthly cash flow',
      icon: Icons.checklist_rounded,
      accent: ModernDialogAccent.brand,
      confirmLabel: widget.existing == null ? 'Save Item' : 'Update Item',
      confirmKey: const Key('bucket_save_btn'),
      onConfirm: _submit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.existing == null) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < _templates.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    ActionChip(
                      label: Text(_templates[i].label),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _nameCtrl.text = _templates[i].name;
                          _priority = _templates[i].priority;
                          _errorText = null;
                        });
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          FintechTextField(
            key: const Key('bucket_name_field'),
            label: 'What do you plan to buy?',
            hintText: 'e.g. Winter jacket, Fridge repair, Headphones',
            controller: _nameCtrl,
            compact: true,
            leadingIcon: Icons.shopping_bag_outlined,
            textCapitalization: TextCapitalization.sentences,
            errorText: _errorText != null && _nameCtrl.text.trim().isEmpty
                ? _errorText
                : null,
            onChanged: (_) {
              if (_errorText != null) setState(() => _errorText = null);
            },
          ),
          const SizedBox(height: 10),
          FintechTextField(
            key: const Key('bucket_amount_field'),
            label: 'Estimated Cost (${widget.currencyCode})',
            controller: _amountCtrl,
            compact: true,
            leadingIcon: Icons.payments_outlined,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            errorText: _errorText != null && _parseMinor(_amountCtrl.text) <= 0
                ? _errorText
                : null,
            onChanged: (_) => setState(() => _errorText = null),
          ),
          if (preview != null) ...[
            const SizedBox(height: 8),
            AnimatedContainer(
              duration: AppMotion.resolve(context, AppMotion.fast),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: prevBg.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: prevFg.withValues(alpha: 0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(prevIcon, size: 16, color: prevFg),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          preview.verdictLabel,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: prevFg,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          preview.guidance,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: scheme.onSurface.withValues(alpha: 0.8),
                                height: 1.3,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Priority Level',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) {
              final tileWidth = constraints.maxWidth >= 340
                  ? (constraints.maxWidth - 8) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in BucketPriority.values)
                    SizedBox(
                      width: tileWidth,
                      child: _PriorityOptionCard(
                        key: Key('bucket_priority_${p.wireValue}'),
                        priority: p,
                        selected: _priority == p,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _priority = p);
                        },
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            'Target Month',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final entry in [
                (key: baseKey, label: 'This (${monthChipLabel(baseKey)})'),
                (key: nextKey, label: 'Next (${monthChipLabel(nextKey)})'),
                (key: plus2Key, label: '+2 mo (${monthChipLabel(plus2Key)})'),
              ])
                ChoiceChip(
                  label: Text(entry.label),
                  selected: _targetMonthKey == entry.key,
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    setState(() => _targetMonthKey = entry.key);
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _dueDateLocal ?? now,
                      firstDate: DateTime(now.year - 1),
                      lastDate: DateTime(now.year + 3),
                    );
                    if (picked != null && mounted) {
                      setState(() => _dueDateLocal = picked);
                    }
                  },
                  icon: const Icon(Icons.event_outlined, size: 17),
                  label: Text(
                    _dueDateLocal != null
                        ? 'Due: ${DateFormat('d MMM yyyy').format(_dueDateLocal!)}'
                        : 'Optional Due Date',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (_dueDateLocal != null) ...[
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Clear due date',
                  onPressed: () => setState(() => _dueDateLocal = null),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: cfo.surfaceTonal,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: cfo.divider),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.notifications_active_outlined,
                  size: 18,
                  color: _reminderEnabled ? scheme.primary : cfo.subtleText,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Purchase Reminder',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        _dueDateLocal != null
                            ? 'Alerts 9:00 AM the day before due date'
                            : 'Alerts tomorrow at 9:00 AM',
                        style: Theme.of(
                          context,
                        ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  key: const Key('bucket_reminder_switch'),
                  value: _reminderEnabled,
                  onChanged: (v) => setState(() => _reminderEnabled = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          FintechDropdownField<String>(
            label: 'Category (Optional)',
            value: _categoryId ?? _noCatSentinel,
            options: catOptions,
            leadingIcon: Icons.category_outlined,
            compact: true,
            onChanged: (val) => setState(
              () => _categoryId = val == _noCatSentinel ? null : val,
            ),
          ),
          const SizedBox(height: 10),
          FintechTextField(
            label: 'Note (Optional)',
            controller: _noteCtrl,
            compact: true,
            leadingIcon: Icons.notes_rounded,
          ),
        ],
      ),
    );
  }
}

class _PriorityOptionCard extends StatelessWidget {
  const _PriorityOptionCard({
    required this.priority,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final BucketPriority priority;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, Color tint) = switch (priority) {
      BucketPriority.urgent => (Icons.priority_high_rounded, cfo.expense),
      BucketPriority.essential => (Icons.verified_outlined, scheme.primary),
      BucketPriority.nice => (Icons.auto_awesome_outlined, cfo.warning),
      BucketPriority.dream => (Icons.star_outline_rounded, cfo.accentCyan),
    };

    return Material(
      color: selected ? tint.withValues(alpha: 0.13) : cfo.surfaceTonal,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        side: BorderSide(
          color: selected ? tint : cfo.divider,
          width: selected ? 1.6 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: tint),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      priority.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: selected ? tint : scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                priority.shortHint,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cfo.subtleText,
                  fontSize: 10.5,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
