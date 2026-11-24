import 'dart:collection';
import 'dart:convert';

enum LogSeverity { debug, info, warning, error, critical }

/// Structured diagnostic entry stripped of all financial/PII/secret fields.
final class RedactedLogEntry {
  const RedactedLogEntry({
    required this.timestampUtc,
    required this.severity,
    required this.module,
    required this.eventName,
    this.requestId,
    this.errorCategory,
    this.metadata = const {},
  });

  final DateTime timestampUtc;
  final LogSeverity severity;
  final String module;
  final String eventName;
  final String? requestId;
  final String? errorCategory;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => {
    'timestamp_utc': timestampUtc.toUtc().toIso8601String(),
    'severity': severity.name,
    'module': module,
    'event_name': eventName,
    if (requestId != null) 'request_id': requestId,
    if (errorCategory != null) 'error_category': errorCategory,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };
}

/// Centralized structured logger enforcing `LOGGING_AND_MONITORING.md`.
/// Automatically redacts sensitive keys and values before emitting or buffering.
final class RedactingLogger {
  RedactingLogger({
    int maxBufferedEntries = 200,
    void Function(String jsonLine)? sink,
  }) : _maxBufferedEntries = maxBufferedEntries,
       _sink = sink;

  final int _maxBufferedEntries;
  final void Function(String jsonLine)? _sink;
  final ListQueue<RedactedLogEntry> _buffer = ListQueue<RedactedLogEntry>();

  static const Set<String> _prohibitedKeySubstrings = {
    'password',
    'passwd',
    'passphrase',
    'token',
    'authorization',
    'auth_header',
    'secret',
    'key',
    'pin',
    'amount',
    'balance',
    'description',
    'memo',
    'note',
    'payee',
    'account_number',
    'iban',
    'card_number',
    'cvv',
    'csv',
    'payload',
    'email',
    'phone',
    'biometric',
  };

  static final RegExp _bearerPattern = RegExp(
    r'Bearer\s+[A-Za-z0-9\-._~+/]+=*',
    caseSensitive: false,
  );
  static final RegExp _jwtPattern = RegExp(
    r'eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}',
  );
  static final RegExp _emailPattern = RegExp(
    r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}',
  );

  List<RedactedLogEntry> get recentEntries => List.unmodifiable(_buffer);

  void log({
    required LogSeverity severity,
    required String module,
    required String eventName,
    String? requestId,
    String? errorCategory,
    Map<String, Object?> metadata = const {},
  }) {
    final sanitized = sanitizeMap(metadata);
    final entry = RedactedLogEntry(
      timestampUtc: DateTime.now().toUtc(),
      severity: severity,
      module: module,
      eventName: sanitizeString(eventName),
      requestId: requestId,
      errorCategory: errorCategory,
      metadata: sanitized,
    );

    if (_buffer.length >= _maxBufferedEntries) {
      _buffer.removeFirst();
    }
    _buffer.addLast(entry);

    final serialized = jsonEncode(entry.toJson());
    _sink?.call(serialized);
  }

  void info(
    String module,
    String eventName, {
    String? requestId,
    Map<String, Object?> metadata = const {},
  }) => log(
    severity: LogSeverity.info,
    module: module,
    eventName: eventName,
    requestId: requestId,
    metadata: metadata,
  );

  void warning(
    String module,
    String eventName, {
    String? requestId,
    String? errorCategory,
    Map<String, Object?> metadata = const {},
  }) => log(
    severity: LogSeverity.warning,
    module: module,
    eventName: eventName,
    requestId: requestId,
    errorCategory: errorCategory,
    metadata: metadata,
  );

  void error(
    String module,
    String eventName, {
    String? requestId,
    String? errorCategory,
    Map<String, Object?> metadata = const {},
  }) => log(
    severity: LogSeverity.error,
    module: module,
    eventName: eventName,
    requestId: requestId,
    errorCategory: errorCategory,
    metadata: metadata,
  );

  /// Produces a copyable redacted diagnostic bundle for user support requests.
  String exportSupportDiagnostics({
    required String appVersion,
    required String platform,
    required String supportCorrelationId,
  }) {
    return const JsonEncoder.withIndent('  ').convert({
      'support_id': supportCorrelationId,
      'app_version': appVersion,
      'platform': platform,
      'generated_at_utc': DateTime.now().toUtc().toIso8601String(),
      'events': _buffer.map((e) => e.toJson()).toList(),
    });
  }

  static Map<String, Object?> sanitizeMap(Map<String, Object?> input) {
    final out = <String, Object?>{};
    for (final entry in input.entries) {
      final lowerKey = entry.key.toLowerCase();
      final isProhibited = _prohibitedKeySubstrings.any(lowerKey.contains);
      if (isProhibited) {
        out[entry.key] = '[REDACTED]';
      } else {
        out[entry.key] = _sanitizeValue(entry.value);
      }
    }
    return out;
  }

  static Object? _sanitizeValue(Object? value) {
    if (value == null || value is bool) return value;
    if (value is num) return value;
    if (value is String) return sanitizeString(value);
    if (value is Map) {
      return sanitizeMap(value.map((k, v) => MapEntry(k.toString(), v)));
    }
    if (value is Iterable) {
      return value.map(_sanitizeValue).toList();
    }
    return sanitizeString(value.toString());
  }

  static String sanitizeString(String input) {
    return input
        .replaceAll(_bearerPattern, 'Bearer [REDACTED]')
        .replaceAll(_jwtPattern, '[REDACTED_JWT]')
        .replaceAll(_emailPattern, '[REDACTED_EMAIL]');
  }
}
