class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://www.rpfwcr.in/api',
  );

  static const String socketHost = String.fromEnvironment(
    'SOCKET_HOST',
    defaultValue: 'www.rpfwcr.in',
  );

  static const int socketPort = int.fromEnvironment(
    'SOCKET_PORT',
    defaultValue: 443,
  );

  static const bool socketUseTls = bool.fromEnvironment(
    'SOCKET_USE_TLS',
    defaultValue: true,
  );

  static const String socketAppKey = String.fromEnvironment(
    'SOCKET_APP_KEY',
    defaultValue: '',
  );

  static const String socketAuthEndpoint = String.fromEnvironment(
    'SOCKET_AUTH_ENDPOINT',
    defaultValue: 'https://www.rpfwcr.in/broadcasting/auth',
  );

  static const bool debugTrackingLogs = bool.fromEnvironment(
    'DEBUG_TRACKING_LOGS',
    defaultValue: false,
  );

  static bool get isSocketConfigured => socketAppKey.trim().isNotEmpty;

  static Uri apiUri(String path) {
    final normalizedBase = apiBaseUrl.endsWith('/')
        ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
        : apiBaseUrl;
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse('$normalizedBase/$normalizedPath');
  }

  static String get publicBaseUrl {
    final normalizedBase = apiBaseUrl.endsWith('/')
        ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
        : apiBaseUrl;
    return normalizedBase.endsWith('/api')
        ? normalizedBase.substring(0, normalizedBase.length - '/api'.length)
        : normalizedBase;
  }
}
