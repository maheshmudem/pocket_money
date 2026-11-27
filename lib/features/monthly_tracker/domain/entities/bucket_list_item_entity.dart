import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import '../../../../core/utilities/id_generator.dart';

/// Priority tiers driving smart Monthly Bucket List budgeting & alerts.
enum BucketPriority {
  urgent('urgent', 'Urgent', 0),
  essential('essential', 'Need', 1),
  nice('nice', 'Nice to have', 2),
  dream('dream', 'Dream / Wish', 3);

  const BucketPriority(this.wireValue, this.label, this.rank);

  final String wireValue;
  final String label;
  final int rank;

  String get shortHint => switch (this) {
    BucketPriority.urgent => 'Must buy now — even if savings slow down',
    BucketPriority.essential => 'Important need — buy if cash flow fits',
    BucketPriority.nice => 'Discretionary buy — only inside wants cap',
    BucketPriority.dream => 'Big wish — convert to Savings Goal',
  };

  static BucketPriority fromWire(String raw) => switch (raw) {
    'urgent' => BucketPriority.urgent,
    'essential' => BucketPriority.essential,
    'nice' => BucketPriority.nice,
    'dream' => BucketPriority.dream,
    _ => BucketPriority.essential,
  };
}

/// Lifecycle status of a Bucket List item.
enum BucketItemStatus {
  planned('planned', 'Planned'),
  purchased('purchased', 'Bought'),
  cancelled('cancelled', 'Cancelled');

  const BucketItemStatus(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static BucketItemStatus fromWire(String raw) => switch (raw) {
    'purchased' => BucketItemStatus.purchased,
    'cancelled' => BucketItemStatus.cancelled,
    _ => BucketItemStatus.planned,
  };
}

/// Planned purchase / wishlist item tracked per financial profile (`SCR-MONTH-001`).
final class BucketListItemEntity extends Equatable {
  const BucketListItemEntity({
    required this.id,
    required this.profileId,
    required this.name,
    required this.estimatedAmountMinor,
    required this.savedAmountMinor,
    required this.reservedInBudgetMinor,
    required this.currencyCode,
    required this.priority,
    required this.targetYearMonth,
    required this.postponeCount,
    required this.status,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.version,
    this.actualAmountMinor,
    this.dueDateUtc,
    this.reminderAtUtc,
    this.categoryId,
    this.linkedGoalId,
    this.purchasedTransactionId,
    this.note,
  });

  final String id;
  final ProfileId profileId;
  final String name;
  final int estimatedAmountMinor;
  final int savedAmountMinor;
  final int reservedInBudgetMinor;
  final int? actualAmountMinor;
  final String currencyCode;
  final BucketPriority priority;
  final String targetYearMonth;
  final String? dueDateUtc;
  final String? reminderAtUtc;
  final String? categoryId;
  final String? linkedGoalId;
  final String? purchasedTransactionId;
  final String? note;
  final int postponeCount;
  final BucketItemStatus status;
  final String createdAtUtc;
  final String updatedAtUtc;
  final int version;

  int get remainingMinor =>
      math.max<int>(0, estimatedAmountMinor - savedAmountMinor);

  double get savedProgressRatio => estimatedAmountMinor > 0
      ? (savedAmountMinor / estimatedAmountMinor).clamp(0.0, 1.0)
      : 0.0;

  BucketListItemEntity copyWith({
    String? name,
    int? estimatedAmountMinor,
    int? savedAmountMinor,
    int? reservedInBudgetMinor,
    int? actualAmountMinor,
    bool clearActualAmount = false,
    String? currencyCode,
    BucketPriority? priority,
    String? targetYearMonth,
    String? dueDateUtc,
    bool clearDueDate = false,
    String? reminderAtUtc,
    bool clearReminder = false,
    String? categoryId,
    bool clearCategory = false,
    String? linkedGoalId,
    bool clearLinkedGoal = false,
    String? purchasedTransactionId,
    bool clearPurchasedTx = false,
    String? note,
    bool clearNote = false,
    int? postponeCount,
    BucketItemStatus? status,
    String? updatedAtUtc,
    int? version,
  }) => BucketListItemEntity(
    id: id,
    profileId: profileId,
    name: name ?? this.name,
    estimatedAmountMinor: estimatedAmountMinor ?? this.estimatedAmountMinor,
    savedAmountMinor: savedAmountMinor ?? this.savedAmountMinor,
    reservedInBudgetMinor: reservedInBudgetMinor ?? this.reservedInBudgetMinor,
    actualAmountMinor: clearActualAmount
        ? null
        : (actualAmountMinor ?? this.actualAmountMinor),
    currencyCode: currencyCode ?? this.currencyCode,
    priority: priority ?? this.priority,
    targetYearMonth: targetYearMonth ?? this.targetYearMonth,
    dueDateUtc: clearDueDate ? null : (dueDateUtc ?? this.dueDateUtc),
    reminderAtUtc: clearReminder ? null : (reminderAtUtc ?? this.reminderAtUtc),
    categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
    linkedGoalId: clearLinkedGoal ? null : (linkedGoalId ?? this.linkedGoalId),
    purchasedTransactionId: clearPurchasedTx
        ? null
        : (purchasedTransactionId ?? this.purchasedTransactionId),
    note: clearNote ? null : (note ?? this.note),
    postponeCount: postponeCount ?? this.postponeCount,
    status: status ?? this.status,
    createdAtUtc: createdAtUtc,
    updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    version: version ?? this.version,
  );

  @override
  List<Object?> get props => [
    id,
    profileId,
    name,
    estimatedAmountMinor,
    savedAmountMinor,
    reservedInBudgetMinor,
    actualAmountMinor,
    currencyCode,
    priority,
    targetYearMonth,
    dueDateUtc,
    reminderAtUtc,
    categoryId,
    linkedGoalId,
    purchasedTransactionId,
    note,
    postponeCount,
    status,
    createdAtUtc,
    updatedAtUtc,
    version,
  ];
}
