import 'package:equatable/equatable.dart';

import '../errors/failures.dart';
import 'currency.dart';
import 'money.dart';

enum FxRoundingMode {
  halfEven('HALF_EVEN'),
  halfUp('HALF_UP');

  const FxRoundingMode(this.wireValue);
  final String wireValue;

  static FxRoundingMode fromWire(String raw) => switch (raw.toUpperCase()) {
    'HALF_UP' => FxRoundingMode.halfUp,
    _ => FxRoundingMode.halfEven,
  };
}

/// Fixed-point exchange rate (`ADR-009`, `CURRENCY_AND_FX.md`).
/// Direction: 1 major unit of [fromCurrencyCode] = (`rateScaled / rateScale`) major units of [toCurrencyCode].
final class FxRate extends Equatable {
  const FxRate({
    required this.fromCurrencyCode,
    required this.toCurrencyCode,
    required this.rateScaled,
    required this.rateScale,
    required this.source,
    required this.effectiveAtUtc,
    this.roundingMode = FxRoundingMode.halfEven,
  }) : assert(rateScaled > 0, 'rateScaled must be positive'),
       assert(rateScale > 0, 'rateScale must be positive');

  static const int defaultScale = 100000000; // 10^8

  factory FxRate.identity(String currencyCode, String effectiveAtUtc) => FxRate(
    fromCurrencyCode: currencyCode.toUpperCase(),
    toCurrencyCode: currencyCode.toUpperCase(),
    rateScaled: defaultScale,
    rateScale: defaultScale,
    source: 'identity',
    effectiveAtUtc: effectiveAtUtc,
  );

  /// Parses a human-entered FX rate string (up to 8 decimal places) purely via integer arithmetic.
  static Result<FxRate> parseDecimalRate({
    required String rawRate,
    required String fromCurrencyCode,
    required String toCurrencyCode,
    required String source,
    required String effectiveAtUtc,
    FxRoundingMode roundingMode = FxRoundingMode.halfEven,
  }) {
    final cleaned = rawRate.trim().replaceAll(',', '');
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(cleaned)) {
      return const FailureResult(
        ValidationFailure(message: 'Enter a valid positive exchange rate.'),
      );
    }

    final parts = cleaned.split('.');
    final whole = parts[0];
    final frac = parts.length > 1 ? parts[1] : '';
    if (frac.length > 8) {
      return const FailureResult(
        ValidationFailure(
          message: 'Exchange rate supports at most 8 decimal places.',
        ),
      );
    }
    final paddedFrac = frac.padRight(8, '0');
    final scaled = BigInt.tryParse('$whole$paddedFrac');
    if (scaled == null ||
        scaled <= BigInt.zero ||
        scaled > BigInt.from(9007199254740991)) {
      return const FailureResult(
        ValidationFailure(message: 'Exchange rate must be greater than zero.'),
      );
    }

    return Success(
      FxRate(
        fromCurrencyCode: fromCurrencyCode.toUpperCase(),
        toCurrencyCode: toCurrencyCode.toUpperCase(),
        rateScaled: scaled.toInt(),
        rateScale: defaultScale,
        source: source,
        effectiveAtUtc: effectiveAtUtc,
        roundingMode: roundingMode,
      ),
    );
  }

  final String fromCurrencyCode;
  final String toCurrencyCode;
  final int rateScaled;
  final int rateScale;
  final String source;
  final String effectiveAtUtc;
  final FxRoundingMode roundingMode;

  String formatDecimal({int maxDecimals = 6}) {
    final bigScaled = BigInt.from(rateScaled);
    final bigScale = BigInt.from(rateScale);
    final whole = bigScaled ~/ bigScale;
    final rem = bigScaled % bigScale;
    if (rem == BigInt.zero) return whole.toString();
    final scaleDigits = rateScale.toString().length - 1;
    var fracStr = rem.toString().padLeft(scaleDigits, '0');
    if (fracStr.length > maxDecimals) {
      fracStr = fracStr.substring(0, maxDecimals);
    }
    fracStr = fracStr.replaceFirst(RegExp(r'0+$'), '');
    return fracStr.isEmpty ? whole.toString() : '$whole.$fracStr';
  }

  @override
  List<Object?> get props => [
    fromCurrencyCode,
    toCurrencyCode,
    rateScaled,
    rateScale,
    source,
    effectiveAtUtc,
    roundingMode,
  ];
}

final class FxConversionResult extends Equatable {
  const FxConversionResult({
    required this.originalAmount,
    required this.convertedAmount,
    required this.appliedRate,
  });

  final Money originalAmount;
  final Money convertedAmount;
  final FxRate appliedRate;

  @override
  List<Object?> get props => [originalAmount, convertedAmount, appliedRate];
}

/// Exact integer/BigInt FX converter (`TC-FIN-014`, `TC-FIN-015`, `TC-FIN-016`).
/// Never uses IEEE-754 floats and never silently substitutes 1:1 when a rate is missing.
abstract final class CurrencyConverter {
  static Result<FxConversionResult> convert({
    required Money original,
    required CurrencySpec originalSpec,
    required CurrencySpec targetSpec,
    required FxRate? fxRate,
    required String fallbackEffectiveAtUtc,
    bool requirePositiveResult = true,
  }) {
    if (original.currencyCode != originalSpec.code) {
      return const FailureResult(
        ValidationFailure(message: 'Original currency specification mismatch.'),
      );
    }

    if (originalSpec.code == targetSpec.code) {
      final identity = FxRate.identity(
        originalSpec.code,
        fallbackEffectiveAtUtc,
      );
      return Success(
        FxConversionResult(
          originalAmount: original,
          convertedAmount: original,
          appliedRate: identity,
        ),
      );
    }

    // TC-FIN-015: Never silently apply 1:1 when FX rate is absent.
    if (fxRate == null) {
      return FailureResult(
        ValidationFailure(
          code: 'FX_RATE_REQUIRED',
          message:
              'An exchange rate from ${originalSpec.code} to ${targetSpec.code} is required. Enter a manual rate or save as draft.',
        ),
      );
    }

    if (fxRate.fromCurrencyCode != originalSpec.code ||
        fxRate.toCurrencyCode != targetSpec.code) {
      return FailureResult(
        ValidationFailure(
          code: 'FX_DIRECTION_MISMATCH',
          message:
              'Expected FX rate direction ${originalSpec.code} -> ${targetSpec.code}, received ${fxRate.fromCurrencyCode} -> ${fxRate.toCurrencyCode}.',
        ),
      );
    }

    final numerator =
        BigInt.from(original.amountMinor) *
        BigInt.from(fxRate.rateScaled) *
        targetSpec.minorFactorBigInt;
    final denominator =
        BigInt.from(fxRate.rateScale) * originalSpec.minorFactorBigInt;

    final roundedMinor = divideAndRound(
      numerator: numerator,
      denominator: denominator,
      mode: fxRate.roundingMode,
    );

    if (requirePositiveResult &&
        original.amountMinor > 0 &&
        roundedMinor <= 0) {
      return FailureResult(
        ValidationFailure(
          code: 'FX_CONVERTED_ZERO',
          message:
              'Converted ${targetSpec.code} amount rounds to zero minor units and cannot be posted.',
        ),
      );
    }

    return Success(
      FxConversionResult(
        originalAmount: original,
        convertedAmount: Money(
          amountMinor: roundedMinor,
          currencyCode: targetSpec.code,
        ),
        appliedRate: fxRate,
      ),
    );
  }

  /// Exact integer rational rounding supporting Banker's Rounding (`HALF_EVEN`)
  /// and standard `HALF_UP` (`TC-FIN-014`).
  static int divideAndRound({
    required BigInt numerator,
    required BigInt denominator,
    required FxRoundingMode mode,
  }) {
    if (denominator <= BigInt.zero) {
      throw ArgumentError('Denominator must be positive.');
    }
    final isNegative = numerator.isNegative;
    final absNum = numerator.abs();
    final quotient = absNum ~/ denominator;
    final remainder = absNum % denominator;
    final twiceRemainder = remainder * BigInt.two;

    BigInt rounded;
    if (twiceRemainder < denominator) {
      rounded = quotient;
    } else if (twiceRemainder > denominator) {
      rounded = quotient + BigInt.one;
    } else {
      // Exact half tie (0.5): apply configured rounding mode.
      rounded = switch (mode) {
        FxRoundingMode.halfEven =>
          quotient.isEven ? quotient : quotient + BigInt.one,
        FxRoundingMode.halfUp => quotient + BigInt.one,
      };
    }

    return (isNegative ? -rounded : rounded).toInt();
  }
}
