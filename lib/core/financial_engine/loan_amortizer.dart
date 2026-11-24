import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import 'fx_rate.dart';

enum LoanInterestMethod {
  reducingBalance('reducing_balance'),
  flat('flat');

  const LoanInterestMethod(this.wireValue);
  final String wireValue;
}

final class LoanInstallmentPlan extends Equatable {
  const LoanInstallmentPlan({
    required this.installmentNumber,
    required this.dueDateUtc,
    required this.principalDueMinor,
    required this.interestDueMinor,
    required this.remainingPrincipalMinor,
  });

  final int installmentNumber;
  final DateTime dueDateUtc;
  final int principalDueMinor;
  final int interestDueMinor;
  final int remainingPrincipalMinor;

  int get totalPaymentMinor => principalDueMinor + interestDueMinor;

  @override
  List<Object?> get props => [
    installmentNumber,
    dueDateUtc,
    principalDueMinor,
    interestDueMinor,
    remainingPrincipalMinor,
  ];
}

/// Deterministic integer minor-unit loan amortization engine (`FR-018`, `DATA-003`).
/// Guarantees `SUM(principalDueMinor) == principalMinor` across the schedule.
abstract final class LoanAmortizer {
  static List<LoanInstallmentPlan> generateSchedule({
    required int principalMinor,
    required int annualInterestRateBps,
    required int termMonths,
    required DateTime startDateUtc,
    LoanInterestMethod method = LoanInterestMethod.reducingBalance,
  }) {
    if (principalMinor <= 0) {
      throw ArgumentError('principalMinor must be positive.');
    }
    if (annualInterestRateBps < 0) {
      throw ArgumentError('annualInterestRateBps cannot be negative.');
    }
    if (termMonths <= 0) {
      throw ArgumentError('termMonths must be positive.');
    }

    final schedule = <LoanInstallmentPlan>[];
    var remaining = principalMinor;

    if (method == LoanInterestMethod.flat || annualInterestRateBps == 0) {
      final basePrincipal = principalMinor ~/ termMonths;
      final totalInterest = annualInterestRateBps == 0
          ? 0
          : CurrencyConverter.divideAndRound(
              numerator:
                  BigInt.from(principalMinor) *
                  BigInt.from(annualInterestRateBps) *
                  BigInt.from(termMonths),
              denominator: BigInt.from(120000), // 10000 bps * 12 months
              mode: FxRoundingMode.halfEven,
            );
      final monthlyInterest = totalInterest ~/ termMonths;
      var interestRemaining = totalInterest;

      for (var i = 1; i <= termMonths; i++) {
        final isLast = i == termMonths;
        final prin = isLast ? remaining : basePrincipal;
        final intr = isLast ? interestRemaining : monthlyInterest;
        remaining -= prin;
        interestRemaining -= intr;
        schedule.add(
          LoanInstallmentPlan(
            installmentNumber: i,
            dueDateUtc: _addMonthsUtc(startDateUtc, i),
            principalDueMinor: prin,
            interestDueMinor: intr,
            remainingPrincipalMinor: remaining,
          ),
        );
      }
      return schedule;
    }

    // Reducing-balance monthly EMI computed to integer minor unit, with exact
    // BigInt monthly interest (`remaining * bps / 120000`) and final-installment reconciliation.
    final monthlyRate = annualInterestRateBps / 120000.0;
    final powFactor = math.pow(1.0 + monthlyRate, termMonths);
    final emiApprox =
        principalMinor * (monthlyRate * powFactor) / (powFactor - 1.0);
    final emiMinor = emiApprox.round();

    for (var i = 1; i <= termMonths; i++) {
      final isLast = i == termMonths;
      final interest = CurrencyConverter.divideAndRound(
        numerator: BigInt.from(remaining) * BigInt.from(annualInterestRateBps),
        denominator: BigInt.from(120000),
        mode: FxRoundingMode.halfEven,
      );

      int principalPart;
      if (isLast) {
        principalPart = remaining;
      } else {
        principalPart = emiMinor - interest;
        if (principalPart < 0) principalPart = 0;
        if (principalPart > remaining) principalPart = remaining;
      }

      remaining -= principalPart;
      schedule.add(
        LoanInstallmentPlan(
          installmentNumber: i,
          dueDateUtc: _addMonthsUtc(startDateUtc, i),
          principalDueMinor: principalPart,
          interestDueMinor: interest,
          remainingPrincipalMinor: remaining,
        ),
      );
    }

    return schedule;
  }

  static DateTime _addMonthsUtc(DateTime date, int monthsToAdd) {
    final totalMonths = (date.year * 12) + (date.month - 1) + monthsToAdd;
    final year = totalMonths ~/ 12;
    final month = (totalMonths % 12) + 1;
    final lastDay = DateTime.utc(year, month + 1, 0).day;
    final day = math.min(date.day, lastDay);
    return DateTime.utc(year, month, day, date.hour, date.minute, date.second);
  }
}
