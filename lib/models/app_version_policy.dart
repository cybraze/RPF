class AppVersionPolicy {
  final int minimumVersionCode;
  final int latestVersionCode;
  final bool forceUpdate;
  final String playStoreUrl;

  const AppVersionPolicy({
    required this.minimumVersionCode,
    required this.latestVersionCode,
    required this.forceUpdate,
    required this.playStoreUrl,
  });

  factory AppVersionPolicy.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map
        ? (json['data'] as Map).cast<String, dynamic>()
        : json;
    final android = data['android'] is Map
        ? (data['android'] as Map).cast<String, dynamic>()
        : data;
    return AppVersionPolicy(
      minimumVersionCode: _asInt(android['minimum_version_code']) ?? 1,
      latestVersionCode: _asInt(android['latest_version_code']) ?? 1,
      forceUpdate: _asBool(android['force_update'] ?? true),
      playStoreUrl: (android['play_store_url'] ??
              'https://play.google.com/store/apps/details?id=in.rpfwcr')
          .toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'minimum_version_code': minimumVersionCode,
      'latest_version_code': latestVersionCode,
      'force_update': forceUpdate,
      'play_store_url': playStoreUrl,
    };
  }

  bool requiresUpdate(int installedVersionCode) {
    return forceUpdate && installedVersionCode < minimumVersionCode;
  }
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

bool _asBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().trim().toLowerCase();
  return text == 'true' || text == '1' || text == 'yes';
}
