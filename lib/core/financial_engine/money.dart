import 'package:equatable/equatable.dart';

import '../errors/failures.dart';
import 'currency.dart';

/// Immutable integer minor-unit monetary value object (`ADR-009`, `NFR-006`).
/// Never uses IEEE-754 floating-point values for persisted or authoritative money.
final class Money extends Equatable implements Comparable<Money> {
  const Money({required this.amountMinor, required this.currencyCode});

  factory Money.zero(String currencyCode) =>
      Money(amountMinor: 0, currencyCode: currencyCode.toUpperCase());

  final int amountMinor;
  final String currencyCode;

  bool get isZero => amountMinor == 0;
  bool get isPositive => amountMinor > 0;
  bool get isNegative => amountMinor < 0;

  Money abs() =>
      Money(amountMinor: amountMinor.abs(), currencyCode: currencyCode);

  Money operator -() =>
      Money(amountMinor: -amountMinor, currencyCode: currencyCode);

  Money operator +(Money other) {
    _assertSameCurrency(other);
    return Money(
      amountMinor: amountMinor + other.amountMinor,
      currencyCode: currencyCode,
    );
  }

  Money operator -(Money other) {
    _assertSameCurrency(other);
    return Money(
      amountMinor: amountMinor - other.amountMinor,
      currencyCode: currencyCode,
    );
  }

  @override
  int compareTo(Money other) {
    _assertSameCurrency(other);
    return amountMinor.compareTo(other.amountMinor);
  }

  void _assertSameCurrency(Money other) {
    if (currencyCode != other.currencyCode) {
      throw LedgerInvariantFailure(
        message:
            'Currency mismatch: cannot combine $currencyCode with ${other.currencyCode} without explicit FX conversion.',
      );
    }
  }

  /// Strictly parses a human-entered decimal string into exact integer minor units
  /// without ever passing through IEEE-754 `double` (`TC-FIN-012`, `TC-FIN-013`).
  static Result<Money> parseDecimal(
    String rawInput, {
    required CurrencySpec currency,
    bool allowZero = false,
    bool allowNegative = false,
  }) {
    final cleaned = rawInput.trim().replaceAll(',', '').replaceAll(' ', '');
    if (cleaned.isEmpty) {
      return const FailureResult(
        ValidationFailure(message: 'Amount is required.'),
      );
    }

    final negative = cleaned.startsWith('-');
    if (negative && !allowNegative) {
      return const FailureResult(
        ValidationFailure(message: 'Amount must be positive.'),
      );
    }

    final unsigned = (cleaned.startsWith('-') || cleaned.startsWith('+'))
        ? cleaned.substring(1)
        : cleaned;

    final validPattern = RegExp(r'^\d+(\.\d+)?$');
    if (!validPattern.hasMatch(unsigned)) {
      return const FailureResult(
        ValidationFailure(message: 'Enter a valid numeric amount.'),
      );
    }

    final parts = unsigned.split('.');
    final majorPart = parts[0];
    final fracPart = parts.length > 1 ? parts[1] : '';

    if (fracPart.length > currency.minorUnit) {
      final msg = currency.minorUnit == 0
          ? '${currency.code} does not support decimal places.'
          : '${currency.code} supports at most ${currency.minorUnit} decimal places.';
      return FailureResult(ValidationFailure(message: msg));
    }

    final paddedFrac = fracPart.padRight(currency.minorUnit, '0');
    final combinedDigits = '$majorPart$paddedFrac';
    final parsedBig = BigInt.tryParse(combinedDigits);
    if (parsedBig == null || parsedBig > BigInt.from(9007199254740991)) {
      return const FailureResult(
        ValidationFailure(message: 'Amount exceeds supported numeric range.'),
      );
    }

    final signedMinor = negative ? -parsedBig.toInt() : parsedBig.toInt();
    if (!allowZero && signedMinor == 0) {
      return const FailureResult(
        ValidationFailure(message: 'Amount must be greater than zero.'),
      );
    }

    return Success(
      Money(amountMinor: signedMinor, currencyCode: currency.code),
    );
  }

  /// Formats monetary value deterministically using integer division and remainder.
  /// Uses Indian numbering grouping (`1,25,000.00`) for INR and international (`125,000.00`) otherwise.
  String format({
    CurrencySpec? spec,
    bool showPlusSign = false,
    bool mask = false,
    bool includeSymbol = true,
  }) {
    final currency =
        spec ??
        CurrencyCatalog.byCode(currencyCode) ??
        CurrencySpec(
          code: currencyCode,
          name: currencyCode,
          minorUnit: 2,
          symbol: currencyCode,
        );

    final prefixSymbol = includeSymbol ? '${currency.symbol} ' : '';
    if (mask) {
      return '$prefixSymbol••••••';
    }

    final isNeg = amountMinor < 0;
    final absVal = amountMinor.abs();
    final factor = currency.minorFactor;
    final major = absVal ~/ factor;
    final minor = absVal % factor;

    final groupedMajor = currency.code == 'INR'
        ? _formatIndianGrouping(major.toString())
        : _formatStandardGrouping(major.toString());

    final decimals = currency.minorUnit > 0
        ? '.${minor.toString().padLeft(currency.minorUnit, '0')}'
        : '';

    final sign = isNeg
        ? '-'
        : (showPlusSign && amountMinor > 0)
        ? '+'
        : '';

    return '$sign$prefixSymbol$groupedMajor$decimals';
  }

  static String _formatStandardGrouping(String digits) {
    final sb = StringBuffer();
    final len = digits.length;
    for (var i = 0; i < len; i++) {
      sb.write(digits[i]);
      final remaining = len - i - 1;
      if (remaining > 0 && remaining % 3 == 0) {
        sb.write(',');
      }
    }
    return sb.toString();
  }

  static String _formatIndianGrouping(String digits) {
    if (digits.length <= 3) return digits;
    final lastThree = digits.substring(digits.length - 3);
    final rest = digits.substring(0, digits.length - 3);
    final sb = StringBuffer();
    for (var i = 0; i < rest.length; i++) {
      sb.write(rest[i]);
      final remaining = rest.length - i - 1;
      if (remaining > 0 && remaining % 2 == 0) {
        sb.write(',');
      }
    }
    sb.write(',');
    sb.write(lastThree);
    return sb.toString();
  }

  @override
  List<Object?> get props => [amountMinor, currencyCode];

  @override
  String toString() => 'Money($amountMinor $currencyCode)';
}
