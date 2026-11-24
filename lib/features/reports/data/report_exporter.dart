import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/financial_engine/currency.dart';
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
