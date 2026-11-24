import 'package:equatable/equatable.dart';

import '../../../../core/financial_engine/money.dart';
import '../../../../core/utilities/id_generator.dart';
import '../../../transactions/domain/entities/transaction_entity.dart';

enum RecurringCadence {
  daily('daily', 'Daily'),
  weekly('weekly', 'Weekly'),
  monthly('monthly', 'Monthly'),
  yearly('yearly', 'Yearly');

  const RecurringCadence(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static RecurringCadence fromWire(String raw) => switch (raw) {
    'daily' => RecurringCadence.daily,
    'weekly' => RecurringCadence.weekly,
    'yearly' => RecurringCadence.yearly,
    _ => RecurringCadence.monthly,
  };
}

final class RecurringRuleEntity extends Equatable {
  const RecurringRuleEntity({
    required this.id,
    required this.profileId,
    required this.name,
    required this.transactionType,
    required this.amount,
    required this.cadence,
    required this.intervalCount,
    required this.nextDueAtUtc,
    required this.autoCreateDraft,
    required this.status,
    this.sourceAccountId,
    this.destinationAccountId,
    this.categoryId,
    this.lastGeneratedOccurrenceKey,
  });

  final String id;
  final ProfileId profileId;
  final String name;
  final TransactionType transactionType;
  final Money amount;
  final RecurringCadence cadence;
  final int intervalCount;
  final String nextDueAtUtc;
  final bool autoCreateDraft;
  final String status;
  final String? sourceAccountId;
  final String? destinationAccountId;
  final String? categoryId;
  final String? lastGeneratedOccurrenceKey;

  @override
  List<Object?> get props => [
    id,
    profileId,
    name,
    transactionType,
    amount,
    cadence,
    intervalCount,
    nextDueAtUtc,
    autoCreateDraft,
    status,
    sourceAccountId,
    destinationAccountId,
    categoryId,
    lastGeneratedOccurrenceKey,
  ];
}

final class LocalNotificationEntity extends Equatable {
  const LocalNotificationEntity({
    required this.id,
    required this.profileId,
    required this.notificationType,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAtUtc,
    this.deepLinkRoute,
  });

  final String id;
  final ProfileId profileId;
  final String notificationType;
  final String title;
  final String body;
  final bool isRead;
  final String createdAtUtc;
  final String? deepLinkRoute;

  @override
  List<Object?> get props => [
    id,
    profileId,
    notificationType,
    title,
    body,
    isRead,
    createdAtUtc,
    deepLinkRoute,
  ];
}
