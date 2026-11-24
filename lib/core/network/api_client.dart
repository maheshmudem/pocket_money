import 'package:dio/dio.dart';

import '../../app/config/environment_config.dart';
import '../errors/failures.dart';
import '../logging/redacting_logger.dart';
import '../security/key_manager.dart';
import '../utilities/id_generator.dart';

/// Centralized Dio HTTP client enforcing `API_CONTRACTS.md`, `API_ERROR_CATALOGUE.md`,
/// and `SEC-001` (in-memory JWT access token, secure-storage refresh rotation,
/// correlation request IDs, and strict log redaction).
class ApiClient {
  ApiClient({
    required EnvironmentConfig config,
    required KeyManager keyManager,
    required IdGenerator idGenerator,
    required RedactingLogger logger,
    Dio? dio,
  }) : _keyManager = keyManager,
       _idGen = idGenerator,
       _logger = logger,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: config.apiBaseUrl,
               connectTimeout: const Duration(seconds: 12),
               receiveTimeout: const Duration(seconds: 20),
               sendTimeout: const Duration(seconds: 20),
               headers: const {
                 'Accept': 'application/json',
                 'Content-Type': 'application/json',
               },
             ),
           ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final reqId = _idGen.nextUuid();
          options.headers['X-Request-ID'] = reqId;
          final token = _accessToken;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (err, handler) async {
          final status = err.response?.statusCode;
          final alreadyRetried = err.requestOptions.extra['_retried'] == true;
          final isAuthRoute = err.requestOptions.path.contains('/auth/');

          if (status == 401 && !alreadyRetried && !isAuthRoute) {
            final refreshed = await _trySingleFlightRefresh();
            if (refreshed) {
              err.requestOptions.extra['_retried'] = true;
              err.requestOptions.headers['Authorization'] =
                  'Bearer $_accessToken';
              try {
                final retryRes = await _dio.fetch<dynamic>(err.requestOptions);
                return handler.resolve(retryRes);
              } on DioException catch (retryErr) {
                return handler.next(retryErr);
              }
            }
          }
          handler.next(err);
        },
      ),
    );
  }

  final Dio _dio;
  final KeyManager _keyManager;
  final IdGenerator _idGen;
  final RedactingLogger _logger;

  // Kept strictly in memory (never persisted to SQLite or plaintext preferences).
  String? _accessToken;
  Future<bool>? _activeRefresh;

  bool get hasAccessToken => _accessToken != null && _accessToken!.isNotEmpty;

  void setAccessToken(String? token) {
    _accessToken = token;
  }

  Future<void> clearTokens() async {
    _accessToken = null;
    await _keyManager.clearRefreshToken();
  }

  Future<Result<Map<String, dynamic>>> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: queryParameters,
      );
      return Success(res.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      return FailureResult(mapDioException(e));
    } catch (_) {
      return const FailureResult(UnexpectedFailure());
    }
  }

  Future<Result<Map<String, dynamic>>> postJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? extraHeaders,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        path,
        data: body,
        options: Options(headers: extraHeaders),
      );
      return Success(res.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      return FailureResult(mapDioException(e));
    } catch (_) {
      return const FailureResult(UnexpectedFailure());
    }
  }

  Future<Result<Map<String, dynamic>>> patchJson(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(path, data: body);
      return Success(res.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      return FailureResult(mapDioException(e));
    } catch (_) {
      return const FailureResult(UnexpectedFailure());
    }
  }

  Future<Result<void>> delete(String path) async {
    try {
      await _dio.delete<dynamic>(path);
      return const Success(null);
    } on DioException catch (e) {
      return FailureResult(mapDioException(e));
    } catch (_) {
      return const FailureResult(UnexpectedFailure());
    }
  }

  Future<bool> _trySingleFlightRefresh() async {
    if (_activeRefresh != null) return _activeRefresh!;
    _activeRefresh = _performRefresh();
    try {
      return await _activeRefresh!;
    } finally {
      _activeRefresh = null;
    }
  }

  Future<bool> _performRefresh() async {
    final refresh = await _keyManager.readRefreshToken();
    if (refresh == null || refresh.isEmpty) return false;
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/auth/refresh/',
        data: {'refresh_token': refresh},
      );
      final data = res.data?['data'] as Map<String, dynamic>?;
      final newAccess = data?['access_token'] as String?;
      final newRefresh = data?['refresh_token'] as String?;
      if (newAccess == null || newRefresh == null) return false;
      _accessToken = newAccess;
      await _keyManager.saveRefreshToken(newRefresh);
      return true;
    } catch (_) {
      await clearTokens();
      return false;
    }
  }

  AppFailure mapDioException(DioException e) {
    final status = e.response?.statusCode;
    final body = e.response?.data;
    String? code;
    String? message;
    String? requestId;
    var fieldErrors = const <String, List<String>>{};

    if (body is Map<String, dynamic>) {
      final errObj = body['error'];
      if (errObj is Map<String, dynamic>) {
        code = errObj['code'] as String?;
        message = errObj['message'] as String?;
        final rawFields = errObj['field_errors'];
        if (rawFields is Map<String, dynamic>) {
          fieldErrors = rawFields.map(
            (k, v) => MapEntry(
              k,
              v is List ? v.map((x) => x.toString()).toList() : [v.toString()],
            ),
          );
        }
      }
      final metaObj = body['meta'];
      if (metaObj is Map<String, dynamic>) {
        requestId = metaObj['request_id'] as String?;
      }
    }

    _logger.warning(
      'network',
      'api_request_failed',
      requestId: requestId,
      errorCategory: code ?? 'HTTP_${status ?? 'NETWORK'}',
      metadata: {'status_code': status},
    );

    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.connectionError) {
      return NetworkFailure(requestId: requestId);
    }

    return switch (status) {
      400 => ValidationFailure(
        code: code ?? 'VALIDATION_ERROR',
        message: message ?? 'Please check the entered information.',
        fieldErrors: fieldErrors,
        requestId: requestId,
      ),
      401 => AuthenticationFailure(
        code: code ?? 'AUTHENTICATION_REQUIRED',
        message: message ?? 'Your session has expired. Please sign in again.',
        requestId: requestId,
      ),
      403 => AuthorizationFailure(
        code: code ?? 'PROFILE_ACCESS_DENIED',
        message: message ?? 'You do not have permission for this profile.',
        requestId: requestId,
      ),
      404 => NotFoundFailure(
        code: code ?? 'RESOURCE_NOT_FOUND',
        message: message ?? 'Requested resource was not found.',
        requestId: requestId,
      ),
      409 => ConflictFailure(
        code: code ?? 'VERSION_CONFLICT',
        message:
            message ?? 'Record changed on another device. Review conflict.',
        requestId: requestId,
      ),
      429 => RateLimitFailure(
        message: message ?? 'Too many requests. Try again shortly.',
        requestId: requestId,
      ),
      503 || 502 || 504 => NetworkFailure(
        code: code ?? 'SERVER_UNAVAILABLE',
        message:
            message ?? 'Service temporarily unavailable. Local data is safe.',
        requestId: requestId,
      ),
      _ => UnexpectedFailure(
        code: code ?? 'INTERNAL_ERROR',
        message: message ?? 'An unexpected server error occurred.',
        requestId: requestId,
      ),
    };
  }
}
