enum AppEnvironment { dev, staging, prod }

/// Compile-time environment configuration injected via `--dart-define`.
/// Never allows runtime endpoint switching in production builds.
final class EnvironmentConfig {
  const EnvironmentConfig({
    required this.environment,
    required this.apiBaseUrl,
    required this.appVersion,
    required this.requireEncryptedDatabase,
    required this.analyticsEnabledByDefault,
  });

  factory EnvironmentConfig.fromDartDefines() {
    const envRaw = String.fromEnvironment(
      'POCKET_CFO_ENV',
      defaultValue: 'dev',
    );
    const apiBaseUrl = String.fromEnvironment(
      'POCKET_CFO_API_URL',
      defaultValue: 'http://10.0.2.2:8000/api/v1',
    );
    const appVersion = String.fromEnvironment(
      'POCKET_CFO_VERSION',
      defaultValue: '1.0.0+1',
    );

    final environment = switch (envRaw.toLowerCase()) {
      'prod' || 'production' => AppEnvironment.prod,
      'staging' => AppEnvironment.staging,
      _ => AppEnvironment.dev,
    };

    if ((environment == AppEnvironment.prod ||
            environment == AppEnvironment.staging) &&
        !apiBaseUrl.startsWith('https://')) {
      throw StateError(
        'Non-HTTPS API endpoint is prohibited in ${environment.name} builds.',
      );
    }

    return EnvironmentConfig(
      environment: environment,
      apiBaseUrl: apiBaseUrl,
      appVersion: appVersion,
      requireEncryptedDatabase: true,
      analyticsEnabledByDefault: false,
    );
  }

  final AppEnvironment environment;
  final String apiBaseUrl;
  final String appVersion;
  final bool requireEncryptedDatabase;
  final bool analyticsEnabledByDefault;

  bool get isProduction => environment == AppEnvironment.prod;
  bool get isStaging => environment == AppEnvironment.staging;
  bool get isDevelopment => environment == AppEnvironment.dev;
}
