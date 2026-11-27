import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/financial_engine/ca_budget_planner_engine.dart';
import '../../../core/financial_engine/currency.dart';
import '../../../core/financial_engine/money.dart';
import '../../dashboard/domain/entities/dashboard_summary.dart';
import '../../import_export/domain/csv_import_engine.dart';
import '../../profiles/domain/entities/profile_entity.dart';
import '../../transactions/domain/entities/transaction_entity.dart';

/// Generates formula-injection-sanitized CSV exports and reconcilable PDF financial
/// statements embedding scope, currency, valuation timestamp, and privacy notice (`FR-016`).
abstract final class ReportExporter {
  static String generateTransactionsCsv({
    required FinancialProfile profile,
    required List<TransactionEntity> transactions,
  }) {
    final rows = <List<dynamic>>[
      [
        'Date (UTC)',
        'Type',
        'Status',
        'Amount',
        'Currency',
        'Base Amount',
        'Base Currency',
        'Source Account',
        'Destination Account',
        'Category',
        'Description',
        'Reference',
      ],
      for (final tx in transactions)
        [
          tx.transactionDateUtc,
          tx.type.label,
          tx.status.label,
          tx.amount.format(
            spec: CurrencyCatalog.byCode(tx.amount.currencyCode),
            includeSymbol: false,
          ),
          tx.amount.currencyCode,
          tx.baseAmount.format(
            spec: CurrencyCatalog.byCode(tx.baseAmount.currencyCode),
            includeSymbol: false,
          ),
          tx.baseAmount.currencyCode,
          CsvImportEngine.sanitizeCsvExportCell(tx.sourceAccountName),
          CsvImportEngine.sanitizeCsvExportCell(tx.destinationAccountName),
          CsvImportEngine.sanitizeCsvExportCell(tx.categoryName),
          CsvImportEngine.sanitizeCsvExportCell(tx.description),
          CsvImportEngine.sanitizeCsvExportCell(tx.externalRef),
        ],
    ];
    return Csv().encode(rows);
  }

  static Future<Uint8List> generateSummaryPdf({
    required FinancialProfile profile,
    required DashboardSummary summary,
    required List<TransactionEntity> transactions,
  }) async {
    final doc = pw.Document();
    final baseSpec = CurrencyCatalog.byCode(profile.baseCurrencyCode);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Pocket CFO — Financial Statement',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Profile: ${profile.name} (${profile.profileType.label})  |  Base Currency: ${profile.baseCurrencyCode}',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                  pw.Text(
                    'Period: ${summary.periodPreset.label}  |  Valuation (UTC): ${summary.valuationTimestampUtc}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
            ],
          ),
          pw.Divider(),
          pw.SizedBox(height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _pdfKpi(
                'Net Worth',
                summary.netWorth.format(spec: baseSpec, includeSymbol: false),
              ),
              _pdfKpi(
                'Total Assets',
                summary.totalAssets.format(
                  spec: baseSpec,
                  includeSymbol: false,
                ),
              ),
              _pdfKpi(
                'Liabilities',
                summary.totalLiabilities.format(
                  spec: baseSpec,
                  includeSymbol: false,
                ),
              ),
              _pdfKpi(
                'Net Cash Flow',
                summary.periodNetCashFlow.format(
                  spec: baseSpec,
                  includeSymbol: false,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Account Balances (Derived from Posted Ledger)',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Account',
              'Type',
              'Currency',
              'Balance',
              'Base Value',
            ],
            data: [
              for (final a in summary.accounts)
                [
                  a.name,
                  a.accountType.label,
                  a.currencyCode,
                  a.balance.format(includeSymbol: false),
                  a.baseBalance.format(spec: baseSpec, includeSymbol: false),
                ],
            ],
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 9,
            ),
            cellStyle: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Transactions (${transactions.length} records)',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Date (UTC)',
              'Type',
              'Category / Account',
              'Description',
              'Base Amount',
            ],
            data: [
              for (final tx in transactions.take(200))
                [
                  tx.transactionDateUtc.substring(0, 10),
                  tx.type.label,
                  tx.categoryName ??
                      tx.destinationAccountName ??
                      tx.sourceAccountName ??
                      '-',
                  tx.description ?? '-',
                  '${tx.baseAmount.format(spec: baseSpec, includeSymbol: false)} ${tx.baseAmount.currencyCode}',
                ],
            ],
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 8,
            ),
            cellStyle: const pw.TextStyle(fontSize: 8),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Notice: Personal/business record-keeping aid only; not certified accounting or tax advice. Protect exported files as sensitive financial records.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );

    return doc.save();
  }

  /// Formula-injection-sanitized Chartered Accountant Budget vs. Actual (BvA) CSV.
  static String generateBudgetVarianceCsv({
    required FinancialProfile profile,
    required CaVarianceStatement statement,
  }) {
    final ccy = statement.currencyCode;
    final spec = CurrencyCatalog.byCode(ccy);
    String fmt(int minor) => Money(
      amountMinor: minor,
      currencyCode: ccy,
    ).format(spec: spec, includeSymbol: false);

    final rows = <List<dynamic>>[
      [
        'Profile',
        'Fiscal Cycle',
        'Period',
        'Category',
        'Cost Class',
        'Budgeted',
        'Actual',
        'Variance (Budget - Actual)',
        'Variance %',
        'CA Status (F/U)',
        'Pro-Rata Expected',
        'Projected End',
        'Currency',
      ],
      for (final line in statement.lines)
        [
          CsvImportEngine.sanitizeCsvExportCell(profile.name),
          CsvImportEngine.sanitizeCsvExportCell(
            statement.window.fiscalCycleLabel,
          ),
          CsvImportEngine.sanitizeCsvExportCell(statement.window.label),
          CsvImportEngine.sanitizeCsvExportCell(line.categoryName),
          CsvImportEngine.sanitizeCsvExportCell(line.costClass.label),
          fmt(line.budgetedMinor),
          fmt(line.actualMinor),
          fmt(line.varianceMinor),
          '${line.variancePercent.toStringAsFixed(1)}%',
          line.isUnbudgeted ? 'UNBUDGETED (U)' : (line.isFavorable ? 'F' : 'U'),
          fmt(line.expectedToDateMinor),
          fmt(line.projectedEndMinor),
          ccy,
        ],
      [
        CsvImportEngine.sanitizeCsvExportCell(profile.name),
        CsvImportEngine.sanitizeCsvExportCell(
          statement.window.fiscalCycleLabel,
        ),
        CsvImportEngine.sanitizeCsvExportCell(statement.window.label),
        'TOTAL',
        'ALL CLASSES',
        fmt(statement.totalBudgetedMinor),
        fmt(statement.totalActualMinor),
        fmt(statement.totalVarianceMinor),
        '${statement.totalVariancePercent.toStringAsFixed(1)}%',
        statement.netCaCode,
        fmt(statement.expectedToDateMinor),
        fmt(statement.projectedEndMinor),
        ccy,
      ],
    ];
    return Csv().encode(rows);
  }

  /// Generates a Chartered Accountant (CA) Budget vs. Actual (BvA) Variance Statement PDF.
  static Future<Uint8List> generateBudgetVariancePdf({
    required FinancialProfile profile,
    required CaVarianceStatement statement,
    required SafeToSpendSnapshot safeToSpend,
    required List<SinkingFundAccrual> sinkingFunds,
    required String generatedAtUtc,
  }) async {
    final doc = pw.Document();
    final ccy = statement.currencyCode;
    final spec = CurrencyCatalog.byCode(ccy);
    String fmt(int minor) =>
        '$ccy ${Money(amountMinor: minor, currencyCode: ccy).format(spec: spec, includeSymbol: false)}';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Pocket CFO - CA Budget vs. Actual (BvA) Variance Statement',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Profile: ${profile.name} (${profile.profileType.label})  |  Currency: $ccy',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.Text(
                'Period: ${statement.window.label.replaceAll('–', '-')}  |  Cycle: ${statement.window.fiscalCycleLabel.replaceAll('–', '-')}  |  Generated (UTC): $generatedAtUtc',
                style: const pw.TextStyle(fontSize: 8.5),
              ),
            ],
          ),
          pw.Divider(),
          pw.SizedBox(height: 6),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _pdfKpi('Total Budgeted', fmt(statement.totalBudgetedMinor)),
              _pdfKpi('Total Actual', fmt(statement.totalActualMinor)),
              _pdfKpi(
                'Net Variance (${statement.netCaCode})',
                fmt(statement.totalVarianceMinor),
              ),
              _pdfKpi('True Safe-to-Spend', fmt(safeToSpend.safeToSpendMinor)),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Cost Behavior Mix & Liquidity Summary',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Fixed Needs',
              'Variable Wants',
              'Tax & Statutory',
              'Savings & CapEx',
              'Unbudgeted Spend',
            ],
            data: [
              [
                fmt(statement.fixedNeedActualMinor),
                fmt(statement.variableWantActualMinor),
                fmt(statement.taxStatutoryActualMinor),
                fmt(statement.savingsCapexActualMinor),
                fmt(statement.unbudgetedSpendMinor),
              ],
            ],
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 8.5,
            ),
            cellStyle: const pw.TextStyle(fontSize: 8.5),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Line-by-Line Budget vs. Actual Variance (${statement.lines.length} Categories)',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Category',
              'Cost Class',
              'Budgeted',
              'Actual',
              'Variance',
              'Var %',
              'Status',
            ],
            data: [
              for (final line in statement.lines)
                [
                  line.categoryName,
                  line.costClass.label,
                  fmt(line.budgetedMinor),
                  fmt(line.actualMinor),
                  fmt(line.varianceMinor),
                  '${line.variancePercent.toStringAsFixed(1)}%',
                  line.isUnbudgeted ? 'UNBUDGETED' : line.caCode,
                ],
              [
                'TOTAL',
                'ALL',
                fmt(statement.totalBudgetedMinor),
                fmt(statement.totalActualMinor),
                fmt(statement.totalVarianceMinor),
                '${statement.totalVariancePercent.toStringAsFixed(1)}%',
                statement.netCaCode,
              ],
            ],
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 8,
            ),
            cellStyle: const pw.TextStyle(fontSize: 8),
          ),
          if (sinkingFunds.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text(
              'Monthly Sinking Fund Provisions (${sinkingFunds.length} Active Targets)',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.TableHelper.fromTextArray(
              headers: const [
                'Provision Target',
                'Remaining Gap',
                'Months Left',
                'Monthly Accrual',
              ],
              data: [
                for (final sf in sinkingFunds)
                  [
                    sf.name,
                    fmt(sf.remainingMinor),
                    '${sf.monthsRemaining} mo',
                    fmt(sf.monthlyAccrualMinor),
                  ],
              ],
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 8.5,
              ),
              cellStyle: const pw.TextStyle(fontSize: 8.5),
            ),
          ],
          pw.SizedBox(height: 14),
          pw.Text(
            'F = Favorable Variance (Actual <= Budget)  |  U = Unfavorable Variance (Actual > Budget or Unbudgeted). Personal/business management report derived from local double-entry ledger.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _pdfKpi(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
