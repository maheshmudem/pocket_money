import 'package:equatable/equatable.dart';

import '../../../../core/financial_engine/money.dart';
import '../../../../core/utilities/id_generator.dart';

final class LoanInstallmentEntity extends Equatable {
  const LoanInstallmentEntity({
    required this.id,
    required this.loanId,
    required this.installmentNumber,
    required this.dueDateUtc,
    required this.principalDueMinor,
    required this.interestDueMinor,
    required this.feeDueMinor,
    required this.status,
    this.paymentTransactionId,
    this.paidAtUtc,
  });

  final String id;
  final String loanId;
  final int installmentNumber;
  final String dueDateUtc;
  final int principalDueMinor;
  final int interestDueMinor;
  final int feeDueMinor;
  final String status;
  final String? paymentTransactionId;
  final String? paidAtUtc;

  int get totalDueMinor => principalDueMinor + interestDueMinor + feeDueMinor;

  @override
  List<Object?> get props => [
    id,
    loanId,
    installmentNumber,
    dueDateUtc,
    principalDueMinor,
    interestDueMinor,
    feeDueMinor,
    status,
    paymentTransactionId,
    paidAtUtc,
  ];
}

final class LoanEntity extends Equatable {
  const LoanEntity({
    required this.id,
    required this.profileId,
    required this.name,
    required this.loanAccountId,
    required this.principal,
    required this.annualInterestRateBps,
    required this.termMonths,
    required this.interestMethod,
    required this.startDateUtc,
    required this.status,
    required this.installments,
    this.fundingAccountId,
  });

  final String id;
  final ProfileId profileId;
  final String name;
  final String loanAccountId;
  final String? fundingAccountId;
  final Money principal;
  final int annualInterestRateBps;
  final int termMonths;
  final String interestMethod;
  final String startDateUtc;
  final String status;
  final List<LoanInstallmentEntity> installments;

  int get paidPrincipalMinor => installments
      .where((i) => i.status == 'paid')
      .fold(0, (s, i) => s + i.principalDueMinor);

  int get remainingPrincipalMinor =>
      (principal.amountMinor - paidPrincipalMinor).clamp(
        0,
        principal.amountMinor,
      );

  int get totalInterestScheduledMinor =>
      installments.fold(0, (s, i) => s + i.interestDueMinor);

  @override
  List<Object?> get props => [
    id,
    profileId,
    name,
    loanAccountId,
    fundingAccountId,
    principal,
    annualInterestRateBps,
    termMonths,
    interestMethod,
    startDateUtc,
    status,
    installments,
  ];
}
