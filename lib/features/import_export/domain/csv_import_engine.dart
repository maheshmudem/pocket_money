import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:csv/csv.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/financial_engine/currency.dart';
import '../../../../core/financial_engine/money.dart';
import '../../../../core/utilities/id_generator.dart';

final class CsvColumnMapping extends Equatable {
  const CsvColumnMapping({
    required this.dateColumnIndex,
    required this.descriptionColumnIndex,
    this.signedAmountColumnIndex,
    this.debitColumnIndex,
    this.creditColumnIndex,
    this.currencyColumnIndex,
    this.externalRefColumnIndex,
    this.hasHeaderRow = true,
    this.defaultCurrencyCode = 'INR',
  });

  final int dateColumnIndex;
  final int descriptionColumnIndex;
  final int? signedAmountColumnIndex;
  final int? debitColumnIndex;
  final int? creditColumnIndex;
  final int? currencyColumnIndex;
  final int? externalRefColumnIndex;
  final bool hasHeaderRow;
  final String defaultCurrencyCode;

  @override
  List<Object?> get props => [
    dateColumnIndex,
    descriptionColumnIndex,
    signedAmountColumnIndex,
    debitColumnIndex,
    creditColumnIndex,
    currencyColumnIndex,
    externalRefColumnIndex,
    hasHeaderRow,
    defaultCurrencyCode,
  ];
}

enum StagedRowValidationStatus { valid, possibleDuplicate, invalid }

enum StagedRowDecision { pending, importRow, skip, rejected }

final class StagedCsvRow extends Equatable {
  const StagedCsvRow({
    required this.sourceRowNumber,
    required this.fingerprint,
    required this.validationStatus,
    required this.decision,
    this.transactionDateUtc,
    this.description,
    this.amountMinor,
    this.currencyCode,
    this.direction, // 'credit' (income) | 'debit' (expense)
    this.externalRef,
    this.validationMessage,
    this.duplicateCandidateTxId,
  });

  final int sourceRowNumber;
  final String? transactionDateUtc;
  final String? description;
  final int? amountMinor;
  final String? currencyCode;
  final String? direction;
  final String? externalRef;
  final String fingerprint;
  final StagedRowValidationStatus validationStatus;
  final String? validationMessage;
  final String? duplicateCandidateTxId;
  final StagedRowDecision decision;

  StagedCsvRow copyWith({StagedRowDecision? decision}) => StagedCsvRow(
    sourceRowNumber: sourceRowNumber,
    transactionDateUtc: transactionDateUtc,
    description: description,
    amountMinor: amountMinor,
    currencyCode: currencyCode,
    direction: direction,
    externalRef: externalRef,
    fingerprint: fingerprint,
    validationStatus: validationStatus,
    validationMessage: validationMessage,
    duplicateCandidateTxId: duplicateCandidateTxId,
    decision: decision ?? this.decision,
  );

  @override
  List<Object?> get props => [
    sourceRowNumber,
    transactionDateUtc,
    description,
    amountMinor,
    currencyCode,
    direction,
    externalRef,
    fingerprint,
    validationStatus,
    validationMessage,
    duplicateCandidateTxId,
    decision,
  ];
}

/// Pure-Dart CSV parser, validator, duplicate fingerprinter, and spreadsheet
/// formula-injection sanitizer (`FR-015`, `FR-016`, `CSV_IMPORT_SPECIFICATION.md`).
abstract final class CsvImportEngine {
  static const int maxFileBytes = 10 * 1024 * 1024; // 10 MB
  static const int maxRowCount = 25000;

  static Result<List<List<String>>> parseRawCsv(
    String rawContent, {
    String? explicitDelimiter,
  }) {
    final byteLen = utf8.encode(rawContent).length;
    if (byteLen > maxFileBytes) {
      return const FailureResult(
        ImportParsingFailure(
          message: 'CSV file exceeds the 10 MB safety limit.',
        ),
      );
    }

    try {
      final codec = Csv(
        fieldDelimiter: explicitDelimiter ?? ',',
        autoDetect: explicitDelimiter == null,
        skipEmptyLines: true,
        dynamicTyping: false,
      );
      final decoded = codec.decode(rawContent);
      if (decoded.length > maxRowCount) {
        return const FailureResult(
          ImportParsingFailure(
            message: 'CSV exceeds the 25,000-row batch safety limit.',
          ),
        );
      }
      final rows = decoded
          .map((row) => row.map((cell) => cell?.toString() ?? '').toList())
          .toList();
      return Success(rows);
    } catch (_) {
      return const FailureResult(
        ImportParsingFailure(
          message:
              'Unable to parse CSV file. Verify encoding (UTF-8) and delimiters.',
        ),
      );
    }
  }

  /// Normalizes parsed CSV rows against [mapping], detects probable duplicates
  /// using [existingFingerprints] and [existingExternalRefs] (`AC-CSV-001`, `TC-FIN-018`).
  static List<StagedCsvRow> stageRows({
    required ProfileId profileId,
    required String accountId,
    required List<List<String>> rawRows,
    required CsvColumnMapping mapping,
    required Map<String, String> existingFingerprints,
    required Map<String, String> existingExternalRefs,
  }) {
    final startIdx = mapping.hasHeaderRow ? 1 : 0;
    final staged = <StagedCsvRow>[];
    final seenInFile = <String>{};

    for (var i = startIdx; i < rawRows.length; i++) {
      final row = rawRows[i];
      final rowNum = i + 1;

      String cell(int? idx) =>
          (idx != null && idx >= 0 && idx < row.length) ? row[idx].trim() : '';

      final rawDate = cell(mapping.dateColumnIndex);
      final rawDesc = cell(mapping.descriptionColumnIndex);
      final rawExtRef = cell(mapping.externalRefColumnIndex);
      final rawCurrency = cell(mapping.currencyColumnIndex);
      final currCode =
          (rawCurrency.isNotEmpty ? rawCurrency : mapping.defaultCurrencyCode)
              .toUpperCase();

      final parsedDate = _parseFlexibleDateUtc(rawDate);
      final currSpec = CurrencyCatalog.byCode(currCode);

      if (parsedDate == null) {
        staged.add(
          _invalidRow(rowNum, rawDesc, 'Unrecognized date format: "$rawDate"'),
        );
        continue;
      }
      if (currSpec == null) {
        staged.add(
          _invalidRow(rowNum, rawDesc, 'Unsupported currency: "$currCode"'),
        );
        continue;
      }

      // Resolve amount & direction from either signed amount OR separate debit/credit columns.
      int? amountMinor;
      String? direction;

      if (mapping.signedAmountColumnIndex != null) {
        final rawAmt = cell(mapping.signedAmountColumnIndex);
        final parsed = Money.parseDecimal(
          rawAmt,
          currency: currSpec,
          allowNegative: true,
        );
        if (parsed.isFailure) {
          staged.add(
            _invalidRow(rowNum, rawDesc, parsed.failureOrNull!.message),
          );
          continue;
        }
        final m = parsed.valueOrNull!;
        amountMinor = m.amountMinor.abs();
        direction = m.amountMinor < 0 ? 'debit' : 'credit';
      } else {
        final rawDebit = cell(mapping.debitColumnIndex);
        final rawCredit = cell(mapping.creditColumnIndex);
        if (rawDebit.isNotEmpty && rawCredit.isEmpty) {
          final parsed = Money.parseDecimal(rawDebit, currency: currSpec);
          if (parsed.isFailure) {
            staged.add(
              _invalidRow(rowNum, rawDesc, parsed.failureOrNull!.message),
            );
            continue;
          }
          amountMinor = parsed.valueOrNull!.amountMinor;
          direction = 'debit';
        } else if (rawCredit.isNotEmpty && rawDebit.isEmpty) {
          final parsed = Money.parseDecimal(rawCredit, currency: currSpec);
          if (parsed.isFailure) {
            staged.add(
              _invalidRow(rowNum, rawDesc, parsed.failureOrNull!.message),
            );
            continue;
          }
          amountMinor = parsed.valueOrNull!.amountMinor;
          direction = 'credit';
        } else {
          staged.add(
            _invalidRow(
              rowNum,
              rawDesc,
              'Provide either a Debit or Credit amount (not both/empty).',
            ),
          );
          continue;
        }
      }

      final dateIso = parsedDate.toIso8601String();
      final fp = computeFingerprint(
        profileId: profileId,
        accountId: accountId,
        dateYyyyMmDd: dateIso.substring(0, 10),
        amountMinor: amountMinor,
        currencyCode: currCode,
        direction: direction,
        description: rawDesc,
      );

      final matchedTxId =
          (rawExtRef.isNotEmpty ? existingExternalRefs[rawExtRef] : null) ??
          existingFingerprints[fp];
      final dupInFile = !seenInFile.add(fp);

      if (matchedTxId != null || dupInFile) {
        staged.add(
          StagedCsvRow(
            sourceRowNumber: rowNum,
            transactionDateUtc: dateIso,
            description: rawDesc,
            amountMinor: amountMinor,
            currencyCode: currCode,
            direction: direction,
            externalRef: rawExtRef.isEmpty ? null : rawExtRef,
            fingerprint: fp,
            validationStatus: StagedRowValidationStatus.possibleDuplicate,
            validationMessage: matchedTxId != null
                ? 'Matches an existing transaction in this account (review before importing).'
                : 'Matches another row in this CSV file.',
            duplicateCandidateTxId: matchedTxId,
            decision: StagedRowDecision.skip,
          ),
        );
      } else {
        staged.add(
          StagedCsvRow(
            sourceRowNumber: rowNum,
            transactionDateUtc: dateIso,
            description: rawDesc,
            amountMinor: amountMinor,
            currencyCode: currCode,
            direction: direction,
            externalRef: rawExtRef.isEmpty ? null : rawExtRef,
            fingerprint: fp,
            validationStatus: StagedRowValidationStatus.valid,
            decision: StagedRowDecision.importRow,
          ),
        );
      }
    }

    return staged;
  }

  static String computeFingerprint({
    required ProfileId profileId,
    required String accountId,
    required String dateYyyyMmDd,
    required int amountMinor,
    required String currencyCode,
    required String direction,
    required String description,
  }) {
    final normalizedDesc = description
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final raw =
        '${profileId.value}|$accountId|$dateYyyyMmDd|$amountMinor|${currencyCode.toUpperCase()}|$direction|$normalizedDesc';
    return crypto.sha256.convert(utf8.encode(raw)).toString();
  }

  /// Neutralizes spreadsheet formula injection (`=`, `+`, `-`, `@`, `\t`, `\r`)
  /// before exporting user-supplied text to CSV (`THREAT_MODEL.md`, `FR-016`).
  static String sanitizeCsvExportCell(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final first = raw[0];
    if (first == '=' ||
        first == '+' ||
        first == '-' ||
        first == '@' ||
        first == '\t' ||
        first == '\r') {
      return "'$raw";
    }
    return raw;
  }

  static StagedCsvRow _invalidRow(int rowNum, String desc, String msg) =>
      StagedCsvRow(
        sourceRowNumber: rowNum,
        description: desc,
        fingerprint: 'invalid-$rowNum',
        validationStatus: StagedRowValidationStatus.invalid,
        validationMessage: msg,
        decision: StagedRowDecision.rejected,
      );

  static DateTime? _parseFlexibleDateUtc(String input) {
    final s = input.trim();
    if (s.isEmpty) return null;

    // 1. ISO-8601 (YYYY-MM-DD or full timestamp)
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso.toUtc();

    // 2. DD/MM/YYYY or DD-MM-YYYY (common Indian/UK bank statements)
    final dmy = RegExp(r'^(\d{1,2})[/\-](\d{1,2})[/\-](\d{4})$').firstMatch(s);
    if (dmy != null) {
      final d = int.parse(dmy.group(1)!);
      final m = int.parse(dmy.group(2)!);
      final y = int.parse(dmy.group(3)!);
      if (m >= 1 && m <= 12 && d >= 1 && d <= 31) {
        return DateTime.utc(y, m, d);
      }
    }

    // 3. YYYY/MM/DD
    final ymd = RegExp(r'^(\d{4})/(\d{1,2})/(\d{1,2})$').firstMatch(s);
    if (ymd != null) {
      final y = int.parse(ymd.group(1)!);
      final m = int.parse(ymd.group(2)!);
      final d = int.parse(ymd.group(3)!);
      if (m >= 1 && m <= 12 && d >= 1 && d <= 31) {
        return DateTime.utc(y, m, d);
      }
    }
    return null;
  }
}
