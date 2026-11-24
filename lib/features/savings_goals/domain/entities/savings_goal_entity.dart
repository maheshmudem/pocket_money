import 'package:equatable/equatable.dart';

import '../../../../core/financial_engine/money.dart';
import '../../../../core/utilities/id_generator.dart';

enum GoalFundingMode {
  allocated('allocated', 'Ring-fenced Allocation'),
  accountTransfer('account_transfer', 'Dedicated Account Transfer');

  const GoalFundingMode(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static GoalFundingMode fromWire(String raw) => switch (raw) {
    'account_transfer' => GoalFundingMode.accountTransfer,
    _ => GoalFundingMode.allocated,
  };
}

final class SavingsGoalEntity extends Equatable {
  const SavingsGoalEntity({
    required this.id,
    required this.profileId,
    required this.name,
    required this.targetAmount,
    required this.contributedAmount,
    required this.fundingMode,
    required this.status,
    required this.createdAtUtc,
    this.targetDateUtc,
    this.linkedAccountId,
    this.linkedAccountName,
  });

  final String id;
  final ProfileId profileId;
  final String name;
  final Money targetAmount;
  final Money contributedAmount;
  final GoalFundingMode fundingMode;
  final String status;
  final String createdAtUtc;
  final String? targetDateUtc;
  final String? linkedAccountId;
  final String? linkedAccountName;

  double get progressRatio => targetAmount.amountMinor > 0
      ? (contributedAmount.amountMinor / targetAmount.amountMinor).clamp(
          0.0,
          1.0,
        )
      : 0.0;

  bool get isCompleted =>
      contributedAmount.amountMinor >= targetAmount.amountMinor;

  @override
  List<Object?> get props => [
    id,
    profileId,
    name,
    targetAmount,
    contributedAmount,
    fundingMode,
    status,
    createdAtUtc,
    targetDateUtc,
    linkedAccountId,
    linkedAccountName,
  ];
}
