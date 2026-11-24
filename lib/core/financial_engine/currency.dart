import 'package:equatable/equatable.dart';

/// Immutable ISO-4217 currency specification (`CURRENCY_AND_FX.md`).
final class CurrencySpec extends Equatable {
  const CurrencySpec({
    required this.code,
    required this.name,
    required this.minorUnit,
    required this.symbol,
    this.isActive = true,
  }) : assert(minorUnit >= 0 && minorUnit <= 4, 'minorUnit must be 0..4');

  final String code;
  final String name;
  final int minorUnit;
  final String symbol;
  final bool isActive;

  int get minorFactor => switch (minorUnit) {
    0 => 1,
    1 => 10,
    2 => 100,
    3 => 1000,
    4 => 10000,
    _ => throw RangeError.range(minorUnit, 0, 4, 'minorUnit'),
  };

  BigInt get minorFactorBigInt => BigInt.from(minorFactor);

  @override
  List<Object?> get props => [code, name, minorUnit, symbol, isActive];
}

/// Pure-Dart currency catalog supporting INR (default) and 0/2/3/4 minor-unit currencies.
abstract final class CurrencyCatalog {
  static const String defaultCurrencyCode = 'INR';

  static const Map<String, CurrencySpec> builtIn = {
    'INR': CurrencySpec(
      code: 'INR',
      name: 'Indian Rupee',
      minorUnit: 2,
      symbol: '₹',
    ),
    'USD': CurrencySpec(
      code: 'USD',
      name: 'US Dollar',
      minorUnit: 2,
      symbol: '\$',
    ),
    'EUR': CurrencySpec(code: 'EUR', name: 'Euro', minorUnit: 2, symbol: '€'),
    'GBP': CurrencySpec(
      code: 'GBP',
      name: 'British Pound',
      minorUnit: 2,
      symbol: '£',
    ),
    'AED': CurrencySpec(
      code: 'AED',
      name: 'UAE Dirham',
      minorUnit: 2,
      symbol: 'د.إ',
    ),
    'SGD': CurrencySpec(
      code: 'SGD',
      name: 'Singapore Dollar',
      minorUnit: 2,
      symbol: 'S\$',
    ),
    'AUD': CurrencySpec(
      code: 'AUD',
      name: 'Australian Dollar',
      minorUnit: 2,
      symbol: 'A\$',
    ),
    'CAD': CurrencySpec(
      code: 'CAD',
      name: 'Canadian Dollar',
      minorUnit: 2,
      symbol: 'C\$',
    ),
    'CHF': CurrencySpec(
      code: 'CHF',
      name: 'Swiss Franc',
      minorUnit: 2,
      symbol: 'CHF',
    ),
    'JPY': CurrencySpec(
      code: 'JPY',
      name: 'Japanese Yen',
      minorUnit: 0,
      symbol: '¥',
    ),
    'KRW': CurrencySpec(
      code: 'KRW',
      name: 'South Korean Won',
      minorUnit: 0,
      symbol: '₩',
    ),
    'KWD': CurrencySpec(
      code: 'KWD',
      name: 'Kuwaiti Dinar',
      minorUnit: 3,
      symbol: 'KD',
    ),
    'BHD': CurrencySpec(
      code: 'BHD',
      name: 'Bahraini Dinar',
      minorUnit: 3,
      symbol: 'BD',
    ),
    'OMR': CurrencySpec(
      code: 'OMR',
      name: 'Omani Rial',
      minorUnit: 3,
      symbol: 'OMR',
    ),
    'CLF': CurrencySpec(
      code: 'CLF',
      name: 'Chilean Unit of Account (UF)',
      minorUnit: 4,
      symbol: 'UF',
    ),
  };

  static CurrencySpec? byCode(String code) => builtIn[code.toUpperCase()];

  static CurrencySpec requireByCode(String code) {
    final spec = byCode(code);
    if (spec == null) {
      throw ArgumentError('Unsupported currency code: $code');
    }
    return spec;
  }
}
