import 'package:equatable/equatable.dart';

/// Base typed failure hierarchy mapped at repository/service boundaries.
/// Never exposes raw SQL, stack traces, secrets, or server internals to UI.
sealed class AppFailure extends Equatable {
  const AppFailure({
    required this.code,
    required this.message,
    this.retryable = false,
    this.requestId,
    this.fieldErrors = const {},
  });

  final String code;
  final String message;
  final bool retryable;
  final String? requestId;
  final Map<String, List<String>> fieldErrors;

  @override
  List<Object?> get props => [code, message, retryable, requestId, fieldErrors];
}

final class ValidationFailure extends AppFailure {
  const ValidationFailure({
    required super.message,
    super.code = 'VALIDATION_ERROR',
    super.fieldErrors,
    super.requestId,
  }) : super(retryable: false);
}

final class AuthenticationFailure extends AppFailure {
  const AuthenticationFailure({
    super.message = 'Your session has expired. Please sign in again.',
    super.code = 'AUTHENTICATION_REQUIRED',
    super.requestId,
  }) : super(retryable: false);
}

final class AuthorizationFailure extends AppFailure {
  const AuthorizationFailure({
    super.message =
        'You do not have permission to perform this action in this profile.',
    super.code = 'PROFILE_ACCESS_DENIED',
    super.requestId,
  }) : super(retryable: false);
}

final class NotFoundFailure extends AppFailure {
  const NotFoundFailure({
    super.message = 'The requested record could not be found.',
    super.code = 'RESOURCE_NOT_FOUND',
    super.requestId,
  }) : super(retryable: false);
}

final class ConflictFailure extends AppFailure {
  const ConflictFailure({
    required super.message,
    super.code = 'VERSION_CONFLICT',
    super.requestId,
  }) : super(retryable: false);
}

final class NetworkFailure extends AppFailure {
  const NetworkFailure({
    super.message =
        'Unable to reach the server. Local changes are safely stored and will sync later.',
    super.code = 'SERVER_UNAVAILABLE',
    super.requestId,
  }) : super(retryable: true);
}

final class RateLimitFailure extends AppFailure {
  const RateLimitFailure({
    super.message =
        'Too many requests. Please wait a moment before trying again.',
    super.code = 'RATE_LIMITED',
    this.retryAfterSeconds,
    super.requestId,
  }) : super(retryable: true);

  final int? retryAfterSeconds;

  @override
  List<Object?> get props => [...super.props, retryAfterSeconds];
}

final class DatabaseFailure extends AppFailure {
  const DatabaseFailure({
    super.message =
        'Could not save data securely on this device. No partial changes were committed.',
    super.code = 'DATABASE_ERROR',
    super.requestId,
  }) : super(retryable: false);
}

final class ImportParsingFailure extends AppFailure {
  const ImportParsingFailure({
    required super.message,
    super.code = 'IMPORT_PARSING_ERROR',
    super.fieldErrors,
  }) : super(retryable: false);
}

final class SecurityFailure extends AppFailure {
  const SecurityFailure({required super.message, super.code = 'SECURITY_ERROR'})
    : super(retryable: false);
}

final class LedgerInvariantFailure extends AppFailure {
  const LedgerInvariantFailure({
    required super.message,
    super.code = 'LEDGER_INVARIANT_VIOLATION',
  }) : super(retryable: false);
}

final class UnexpectedFailure extends AppFailure {
  const UnexpectedFailure({
    super.message = 'An unexpected error occurred. Please try again.',
    super.code = 'INTERNAL_ERROR',
    super.requestId,
  }) : super(retryable: false);
}

/// Functional result type avoiding untyped exception control flow in domain/BLoC.
sealed class Result<T> {
  const Result();

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is FailureResult<T>;

  T? get valueOrNull => switch (this) {
    Success<T>(value: final v) => v,
    FailureResult<T>() => null,
  };

  AppFailure? get failureOrNull => switch (this) {
    Success<T>() => null,
    FailureResult<T>(failure: final f) => f,
  };

  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(AppFailure failure) onFailure,
  }) {
    return switch (this) {
      Success<T>(value: final v) => onSuccess(v),
      FailureResult<T>(failure: final f) => onFailure(f),
    };
  }
}

final class Success<T> extends Result<T> {
  const Success(this.value);
  final T value;
}

final class FailureResult<T> extends Result<T> {
  const FailureResult(this.failure);
  final AppFailure failure;
}
